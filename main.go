package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/gorilla/mux"
	_ "github.com/lib/pq"
)

type Tenant struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	// Add more tenant properties as needed
}

// Global database connection
var db *sql.DB

func init() {
	// Database connection parameters
	connStr := "postgres://username:password@localhost:5432/tenants_db?sslmode=disable"
	var err error
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}

	// Test the connection
	err = db.Ping()
	if err != nil {
		log.Fatal(err)
	}

	// Create tenants table if it doesn't exist
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS tenants (
			id VARCHAR(50) PRIMARY KEY,
			name VARCHAR(100) NOT NULL
		)
	`)
	if err != nil {
		log.Fatal(err)
	}
}

func main() {
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
		
		// تقسيم العنوان لاستبعاد رقم المنفذ إذا وجد
		hostParts := strings.Split(host, ":")
		hostWithoutPort := hostParts[0]
		
		// استخراج معرف المستأجر
		tenantID := strings.Split(hostWithoutPort, ".")[0]
		
		fmt.Println("Host:", host, "Host without port:", hostWithoutPort, "TenantID:", tenantID) // للتصحيح
		
		// إذا كان المسار الرئيسي
		if tenantID == "localhost" || tenantID == "127.0.0.1" {
			http.ServeFile(w, r, "frontend/index.html")
			return
		}
		
		// التحقق من وجود المستأجر
		if _, exists := tenants[tenantID]; !exists {
			fmt.Fprintf(w, "Tenant '%s' not found. Available tenants: tenant1, tenant2, tenant3", tenantID)
			return
		}
		
		// تقديم واجهة المستأجر
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
				
	var tenant Tenant
	err := db.QueryRow("SELECT id, name FROM tenants WHERE id = $1", tenantID).Scan(&tenant.ID, &tenant.Name)
	if err == nil {
		fmt.Fprintf(w, "Tenant ID: %s, Name: %s", tenant.ID, tenant.Name)
	} else {
		fmt.Fprintf(w, "Main application - No tenant selected")
	}
}

func getTenantsList(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Query("SELECT id, name FROM tenants")
	if err != nil {
		http.Error(w, "Error fetching tenants", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var tenants []Tenant
	for rows.Next() {
		var t Tenant
		if err := rows.Scan(&t.ID, &t.Name); err != nil {
			http.Error(w, "Error scanning tenants", http.StatusInternalServerError)
			return
		}
		tenants = append(tenants, t)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string][]Tenant{"tenants": tenants})
}

func createTenant(w http.ResponseWriter, r *http.Request) {
	var tenant Tenant
	if err := json.NewDecoder(r.Body).Decode(&tenant); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	_, err := db.Exec("INSERT INTO tenants (id, name) VALUES ($1, $2)", tenant.ID, tenant.Name)
	if err != nil {
		http.Error(w, "Error creating tenant", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Tenant created",
	})
}