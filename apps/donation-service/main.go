package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
)

type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type App struct {
	DB          *sql.DB
	SqsSvc      *sqs.SQS
	SqsQueueURL string
}

// chaosEnabled liga os endpoints/gatilhos de caos usados só na demo de self-healing
// (/debug/crash e o header X-Chaos: error-500). Nunca "true" em produção real.
var chaosEnabled = os.Getenv("CHAOS_ENDPOINTS_ENABLED") == "true"

// --- Golden Metrics: Latência, Tráfego e Taxa de Erro (SLIs do donation-service) ---
var (
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total de requisições HTTP recebidas pelo donation-service",
	}, []string{"method", "path", "status"})

	httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "Latência das requisições HTTP do donation-service",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "path"})

	donationsProcessedTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "donations_processed_total",
		Help: "Total de doações processadas, por status",
	}, []string{"status"})

	sqsPublishFailuresTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "donation_sqs_publish_failures_total",
		Help: "Total de falhas ao publicar evento de doação no SQS após esgotar retries",
	})
)

func main() {
	_ = godotenv.Load()

	shutdownTracing := setupTracing(context.Background())
	defer shutdownTracing(context.Background())

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL é obrigatória")
	}

	db, err := sql.Open("pgx", dbURL)
	if err != nil {
		log.Fatalf("Erro ao abrir conexão com o banco de dados: %v", err)
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	// Não usa log.Fatal aqui por design: se o RDS estiver temporariamente indisponível no
	// boot (failover, manutenção, restart do próprio banco), o processo ainda sobe e responde
	// HTTP - /health reporta "degraded" (503) até a conexão voltar, e o readinessProbe tira o
	// pod do Service sem matar o container. Antes, um log.Fatal aqui criava um efeito cascata:
	// o livenessProbe (que também batia em /health) matava pods saudáveis por causa do banco,
	// e o pod novo nunca conseguia nem terminar de subir enquanto o banco estivesse fora -
	// CrashLoopBackOff permanente pela duração inteira da indisponibilidade do RDS.
	if err := db.Ping(); err != nil {
		log.Printf("Aviso: banco de dados inacessível no boot (%v) - subindo mesmo assim, /health reportará degraded", err)
	} else {
		log.Println("Conectado ao PostgreSQL (donation-service).")
	}

	var sqsSvc *sqs.SQS
	queueURL := os.Getenv("AWS_SQS_URL")
	region := os.Getenv("AWS_REGION")
	if queueURL != "" && region != "" {
		sess, _ := session.NewSession(&aws.Config{Region: aws.String(region)})
		sqsSvc = sqs.New(sess)
		log.Println("Integração com AWS SQS ativada.")
	}

	app := &App{DB: db, SqsSvc: sqsSvc, SqsQueueURL: queueURL}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.HealthHandler)
	mux.HandleFunc("/live", app.LiveHandler)
	mux.Handle("/donations", metricsMiddleware("/donations", http.HandlerFunc(app.DonationHandler)))
	mux.Handle("/metrics", promhttp.Handler())

	// Endpoints de caos - só registrados quando CHAOS_ENDPOINTS_ENABLED=true. Existem para a
	// demonstração de self-healing/MTTR (docs/SRE-SLI-SLO-SLA.md):
	//  - /debug/crash: encerra o processo -> container reinicia no MESMO pod (sem recriar o
	//    pod, sem alterar o Deployment, sem disputa com o selfHeal do ArgoCD) -> os restarts
	//    se acumulam e disparam o alerta DonationServiceCrashLooping.
	//  - header `X-Chaos: error-500` em POST /donations: força um 500 -> a taxa de erro 5xx
	//    do SLI de disponibilidade sobe e dispara o alerta DonationServiceHighErrorRate.
	// Os dois alertas o Alertmanager encaminha ao healer-service. NUNCA habilitar em prod real.
	if chaosEnabled {
		mux.HandleFunc("/debug/crash", crashHandler)
		log.Println("AVISO: endpoints de caos habilitados (CHAOS_ENDPOINTS_ENABLED=true) - use apenas em demonstração")
	}

	handler := otelhttp.NewHandler(mux, "donation-service")

	log.Printf("donation-service rodando na porta %s", port)
	log.Fatal(http.ListenAndServe(":"+port, handler))
}

// metricsMiddleware registra as Golden Metrics (tráfego, latência, erros) por rota.
func metricsMiddleware(path string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		elapsed := time.Since(start).Seconds()
		httpRequestDuration.WithLabelValues(r.Method, path).Observe(elapsed)
		// código numérico ("200","500"...) - mesma convenção do ngo/volunteer-service e o que
		// os alertas de SLO (status=~"5..") e os dashboards esperam. Antes era http.StatusText
		// ("Internal Server Error"), que nunca casava com o regex do alerta HighErrorRate.
		httpRequestsTotal.WithLabelValues(r.Method, path, strconv.Itoa(sw.status)).Inc()
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

// HealthHandler é o alvo do readinessProbe: reflete a saúde real das dependências (banco).
// Um 503 aqui tira o pod do Service - não deve, e não é, usado como livenessProbe (ver
// LiveHandler): matar o processo não resolve o banco estar fora, só causa restart-storm.
func (a *App) HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if err := a.DB.Ping(); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte(`{"status":"degraded","service":"donation-service"}`))
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok","service":"donation-service"}`))
}

// LiveHandler é o alvo do livenessProbe: só confirma que o processo HTTP está respondendo,
// sem checar dependências externas.
func (a *App) LiveHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok","service":"donation-service"}`))
}

// crashHandler encerra o processo com exit(1) logo após responder. Registrado só quando
// CHAOS_ENDPOINTS_ENABLED=true (ver main). Usado pelo scripts/chaos-crash-donation-service.sh.
func crashHandler(w http.ResponseWriter, r *http.Request) {
	log.Println("CHAOS: /debug/crash acionado - encerrando o processo com exit(1)")
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"crashing"}`))
	go func() {
		time.Sleep(150 * time.Millisecond) // garante o flush da resposta antes de sair
		os.Exit(1)
	}()
}

func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	tracer := otel.Tracer("donation-service")
	w.Header().Set("Content-Type", "application/json")

	if r.Method == http.MethodPost {
		ctx, span := tracer.Start(ctx, "create_donation")
		defer span.End()

		// Gatilho de caos p/ a demo do alerta de taxa de erro (só com CHAOS_ENDPOINTS_ENABLED).
		if chaosEnabled && r.Header.Get("X-Chaos") == "error-500" {
			donationsProcessedTotal.WithLabelValues("CHAOS_ERROR").Inc()
			http.Error(w, `{"error":"Erro interno (chaos)"}`, http.StatusInternalServerError)
			return
		}

		var d Donation
		if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
			http.Error(w, `{"error":"Payload inválido"}`, http.StatusBadRequest)
			return
		}

		d.Status = "APPROVED" // Simulação de gateway de pagamento
		err := a.DB.QueryRowContext(ctx,
			"INSERT INTO donations (ngo_id, amount, donor_name, status) VALUES ($1, $2, $3, $4) RETURNING id, created_at",
			d.NgoID, d.Amount, d.DonorName, d.Status,
		).Scan(&d.ID, &d.CreatedAt)

		if err != nil {
			log.Printf("Erro ao salvar doação: %v", err)
			donationsProcessedTotal.WithLabelValues("DB_ERROR").Inc()
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
		donationsProcessedTotal.WithLabelValues(d.Status).Inc()

		if a.SqsSvc != nil {
			// Publicação assíncrona, mas com retry+backoff (evita perda silenciosa de evento
			// só por falha transitória de rede/throttle do SQS). Falha definitiva é registrada
			// em métrica dedicada -> vira alerta -> mensagens já ficam protegidas pela DLQ da fila.
			go a.sendNotificationEventWithRetry(context.Background(), d)
		}

		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(d)
		return
	}

	if r.Method == http.MethodGet {
		_, span := tracer.Start(ctx, "list_donations")
		defer span.End()

		rows, err := a.DB.QueryContext(ctx, "SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations ORDER BY id DESC")
		if err != nil {
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		donations := []Donation{}
		for rows.Next() {
			var d Donation
			rows.Scan(&d.ID, &d.NgoID, &d.Amount, &d.DonorName, &d.Status, &d.CreatedAt)
			donations = append(donations, d)
		}

		json.NewEncoder(w).Encode(donations)
		return
	}

	http.Error(w, `{"error":"Método não permitido"}`, http.StatusMethodNotAllowed)
}

// sendNotificationEventWithRetry tenta publicar o evento até 3 vezes com backoff exponencial.
// Se todas falharem, incrementa métrica que alimenta alerta de SRE (o dado da doação em si
// já está persistido no Postgres - o que se perde é só a notificação assíncrona).
func (a *App) sendNotificationEventWithRetry(ctx context.Context, d Donation) {
	body, _ := json.Marshal(d)
	backoff := 200 * time.Millisecond

	for attempt := 1; attempt <= 3; attempt++ {
		_, err := a.SqsSvc.SendMessage(&sqs.SendMessageInput{
			MessageBody: aws.String(string(body)),
			QueueUrl:    aws.String(a.SqsQueueURL),
		})
		if err == nil {
			return
		}
		log.Printf("Falha ao despachar evento SQS (tentativa %d/3): %v", attempt, err)
		time.Sleep(backoff)
		backoff *= 2
	}

	sqsPublishFailuresTotal.Inc()
	log.Printf("Evento de doação id=%d não pôde ser publicado no SQS após 3 tentativas", d.ID)
}
