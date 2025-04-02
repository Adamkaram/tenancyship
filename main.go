package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/gorilla/mux"
)

type Tenant struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// In-memory storage for tenants
var tenants = make(map[string]Tenant)

type TenantService struct {
	BaseURL string
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func NewTenantService() *TenantService {
	baseURL := getEnvOrDefault("TENANT_SERVICE_URL", "http://localhost:8080")
	return &TenantService{BaseURL: baseURL}
}

func (ts *TenantService) GetTenant(id string) (*Tenant, error) {
	if tenant, exists := tenants[id]; exists {
		return &tenant, nil
	}
	return nil, nil
}

func (ts *TenantService) ListTenants() ([]Tenant, error) {
	var tenantList []Tenant
	for _, tenant := range tenants {
		tenantList = append(tenantList, tenant)
	}
	return tenantList, nil
}

func main() {
	tenantService := NewTenantService()
	r := mux.NewRouter()

	// API routes
	api := r.PathPrefix("/api").Subrouter()
	api.HandleFunc("/tenants", getTenantsList).Methods("GET")
	api.HandleFunc("/tenants", createTenant).Methods("POST")

	// Tenant-specific routes
	r.HandleFunc("/tenant-info", tenantInfoHandler)

	// Move the subdomain handling to the main router
	r.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		host := r.Host

		// Split address to exclude port if present
		hostParts := strings.Split(host, ":")
		hostWithoutPort := hostParts[0]

		// Extract tenant ID
		tenantID := strings.Split(hostWithoutPort, ".")[0]

		fmt.Println("Host:", host, "Host without port:", hostWithoutPort, "TenantID:", tenantID)

		// If main path
		if tenantID == "localhost" || tenantID == "127.0.0.1" {
			http.ServeFile(w, r, "frontend/index.html")
			return
		}

		// Check if tenant exists
		tenant, err := tenantService.GetTenant(tenantID)
		if err != nil {
			http.Error(w, "Error fetching tenant", http.StatusInternalServerError)
			return
		}
		if tenant == nil {
			fmt.Fprintf(w, "Tenant '%s' not found", tenantID)
			return
		}

		// Serve tenant interface
		http.ServeFile(w, r, "frontend/tenant.html")
	})

	// Serve static files
	fs := http.FileServer(http.Dir("./frontend"))
	r.PathPrefix("/static/").Handler(http.StripPrefix("/static/", fs))

	// Use the router as the main handler
	fmt.Println("Server starting on :8080")
	log.Fatal(http.ListenAndServe(":8080", r))
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, "frontend/index.html")
}

func tenantInfoHandler(w http.ResponseWriter, r *http.Request) {
	host := r.Host
	tenantID := strings.Split(host, ".")[0]

	if tenant, exists := tenants[tenantID]; exists {
		fmt.Fprintf(w, "Tenant ID: %s, Name: %s", tenant.ID, tenant.Name)
	} else {
		fmt.Fprintf(w, "Main application - No tenant selected")
	}
}

func getTenantsList(w http.ResponseWriter, r *http.Request) {
	var tenantList []Tenant
	for _, tenant := range tenants {
		tenantList = append(tenantList, tenant)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string][]Tenant{"tenants": tenantList})
}

func createTenant(w http.ResponseWriter, r *http.Request) {
	var tenant Tenant
	if err := json.NewDecoder(r.Body).Decode(&tenant); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	tenants[tenant.ID] = tenant

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Tenant created",
	})
}
