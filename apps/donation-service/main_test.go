package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestMetricsMiddlewareRecordsStatus(t *testing.T) {
	handler := metricsMiddleware("/donations", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
	}))

	req := httptest.NewRequest(http.MethodPost, "/donations", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("esperado status 201, obtido %d", rec.Code)
	}
}

func TestDonationJSONRoundTrip(t *testing.T) {
	d := Donation{ID: 1, NgoID: 2, Amount: 50.5, DonorName: "Jorge", Status: "APPROVED"}

	body, err := json.Marshal(d)
	if err != nil {
		t.Fatalf("erro ao serializar doação: %v", err)
	}

	var decoded Donation
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("erro ao desserializar doação: %v", err)
	}

	if decoded.DonorName != d.DonorName || decoded.Amount != d.Amount {
		t.Fatalf("round-trip divergente: got %+v, want %+v", decoded, d)
	}
}
