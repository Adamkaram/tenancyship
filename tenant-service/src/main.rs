use axum::{
    extract::Path,
    routing::{get, post, delete, put},
    Json, Router,
};
use dotenv::dotenv;
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::net::SocketAddr;
use surrealdb::engine::any::{self, Any};
use surrealdb::opt::auth::Root;
use surrealdb::Surreal;
use tokio::net::TcpListener;
use tower_http::cors::CorsLayer;
use serde_json::Value;
use regex;

// Configuration struct for secrets management
#[derive(Debug, Deserialize)]
struct Config {
    surrealdb_url: String,
    surrealdb_user: String,
    surrealdb_pass: String,
    surrealdb_ns: String,
    surrealdb_db: String,
}

impl Config {
    fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Config {
            surrealdb_url: env::var("SURREALDB_URL")?,
            surrealdb_user: env::var("SURREALDB_USER")?,
            surrealdb_pass: env::var("SURREALDB_PASS")?,
            surrealdb_ns: env::var("SURREALDB_NS")?,
            surrealdb_db: env::var("SURREALDB_DB")?,
        })
    }

    fn from_k8s_secrets() -> Result<Self, Box<dyn std::error::Error>> {
        // In Kubernetes, secrets are mounted at /mnt/secrets/surrealdb-creds/
        const SECRET_PATH: &str = "/mnt/secrets/surrealdb-creds";
        
        Ok(Config {
            surrealdb_url: fs::read_to_string(format!("{}/SURREALDB_URL", SECRET_PATH))?.trim().to_string(),
            surrealdb_user: fs::read_to_string(format!("{}/SURREALDB_USER", SECRET_PATH))?.trim().to_string(),
            surrealdb_pass: fs::read_to_string(format!("{}/SURREALDB_PASS", SECRET_PATH))?.trim().to_string(),
            surrealdb_ns: fs::read_to_string(format!("{}/SURREALDB_NS", SECRET_PATH))?.trim().to_string(),
            surrealdb_db: fs::read_to_string(format!("{}/SURREALDB_DB", SECRET_PATH))?.trim().to_string(),
        })
    }

    async fn from_vault() -> Result<Self, Box<dyn std::error::Error>> {
        let vault_addr = env::var("VAULT_ADDR")?;
        let vault_token = env::var("VAULT_TOKEN")?;
        
        let client = reqwest::Client::new();
        let response = client
            .get(format!("{}/v1/surrealdb/data/tenant-service", vault_addr))
            .header("X-Vault-Token", vault_token)
            .send()
            .await?
            .json::<Value>()
            .await?;

        let data = response["data"]["data"].as_object()
            .ok_or("Invalid Vault response format")?;

        Ok(Config {
            surrealdb_url: data["url"].as_str().unwrap_or("").to_string(),
            surrealdb_user: data["user"].as_str().unwrap_or("").to_string(),
            surrealdb_pass: data["password"].as_str().unwrap_or("").to_string(),
            surrealdb_ns: data["ns"].as_str().unwrap_or("").to_string(),
            surrealdb_db: data["db"].as_str().unwrap_or("").to_string(),
        })
    }
}

// Error handling module
mod error {
    use axum::http::StatusCode;
    use axum::response::IntoResponse;
    use axum::response::Response;
    use axum::Json;
    use std::fmt;

    #[derive(Debug)]
    pub enum Error {
        Db,
        NotFound,
        BadRequest(String),
        Conflict(String),
    }
    
    impl fmt::Display for Error {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            match self {
                Error::Db => write!(f, "database error"),
                Error::NotFound => write!(f, "not found"),
                Error::BadRequest(msg) => write!(f, "bad request: {}", msg),
                Error::Conflict(msg) => write!(f, "conflict: {}", msg),
            }
        }
    }
    
    impl IntoResponse for Error {
        fn into_response(self) -> Response {
            let status = match self {
                Self::Db => StatusCode::INTERNAL_SERVER_ERROR,
                Self::NotFound => StatusCode::NOT_FOUND,
                Self::BadRequest(_) => StatusCode::BAD_REQUEST,
                Self::Conflict(_) => StatusCode::CONFLICT,
            };
            (status, Json(self.to_string())).into_response()
        }
    }

    impl From<surrealdb::Error> for Error {
        fn from(error: surrealdb::Error) -> Self {
            eprintln!("{error}");
            Self::Db
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct Tenant {
    id: String,
    name: String,
    domain: Option<String>,
    ssl_enabled: Option<bool>,
}

// API routes
mod routes {
    use super::*;
    use crate::error::Error;

    const TENANT: &str = "tenant";

    // Helper function to display API documentation
    pub async fn api_docs() -> &'static str {
        r#"
    -----------------------------------------------------------------------------------------------------------------------------------------
            PATH                |           SAMPLE COMMAND                                                                                  
    -----------------------------------------------------------------------------------------------------------------------------------------
    /tenants:                   |  curl -X GET    -H "Content-Type: application/json"                       http://localhost:8080/tenants
      List all tenants          |
                                |
    /tenants/{id}:              |
      Create a tenant           |  curl -X POST   -H "Content-Type: application/json" -d '{"id":"t1","name":"First Tenant"}' http://localhost:8080/tenants/t1
      Get a tenant              |  curl -X GET    -H "Content-Type: application/json"                       http://localhost:8080/tenants/t1
      Update a tenant           |  curl -X PUT    -H "Content-Type: application/json" -d '{"name":"Updated Tenant"}' http://localhost:8080/tenants/t1
      Delete a tenant           |  curl -X DELETE -H "Content-Type: application/json"                       http://localhost:8080/tenants/t1
    
    /tenants/{id}/domain:       |
      Add a domain              |  curl -X POST   -H "Content-Type: application/json" -d '{"domain":"example.com"}' http://localhost:8080/tenants/t1/domain
      Remove a domain           |  curl -X DELETE -H "Content-Type: application/json"                       http://localhost:8080/tenants/t1/domain
                                |
    /domains:                   |  curl -X GET    -H "Content-Type: application/json"                       http://localhost:8080/domains
      List all domains          |
    "#
    }

    pub async fn create_tenant(
        axum::extract::State(db): axum::extract::State<Surreal<Any>>,
        Path(id): Path<String>,
        Json(mut tenant): Json<Tenant>,
    ) -> Result<Json<Tenant>, Error> {
        tenant.id = id.clone();
        
        let created: Option<Tenant> = db
            .create((TENANT, &id))
            .content(tenant.clone())
            .await?;
            
        match created {
            Some(tenant) => Ok(Json(tenant)),
            None => Err(Error::Db),
        }
    }

    pub async fn list_tenants(
        axum::extract::State(db): axum::extract::State<Surreal<Any>>,
    ) -> Result<Json<Vec<Tenant>>, Error> {
        let tenants: Vec<Tenant> = db.select(TENANT).await?;
        Ok(Json(tenants))
    }

    pub async fn get_tenant(
        axum::extract::State(db): axum::extract::State<Surreal<Any>>,
        Path(id): Path<String>,
    ) -> Result<Json<Tenant>, Error> {
        let tenant: Option<Tenant> = db.select((TENANT, &id)).await?;
        
        match tenant {
            Some(tenant) => Ok(Json(tenant)),
            None => Err(Error::NotFound),
        }
    }

    pub async fn update_tenant(
        axum::extract::State(db): axum::extract::State<Surreal<Any>>,
        Path(id): Path<String>,
        Json(mut tenant_data): Json<Tenant>,
    ) -> Result<Json<Tenant>, Error> {
        tenant_data.id = id.clone();
        
        let tenant: Option<Tenant> = db
            .update((TENANT, &id))
            .content(tenant_data)
            .await?;
            
        match tenant {
            Some(tenant) => Ok(Json(tenant)),
            None => Err(Error::NotFound),
        }
    }

    pub async fn delete_tenant(
        axum::extract::State(db): axum::extract::State<Surreal<Any>>,
        Path(id): Path<String>,
    ) -> Result<Json<Tenant>, Error> {
        let tenant: Option<Tenant> = db.delete((TENANT, &id)).await?;
        
        match tenant {
            Some(tenant) => Ok(Json(tenant)),
            None => Err(Error::NotFound),
        }
    }

    #[derive(Debug, Serialize, Deserialize)]
    struct DomainRequest {
        domain: String,
    }

    #[derive(Debug, Serialize, Deserialize)]
    struct DomainInfo {
        tenant_id: String,
        domain: String,
        ssl_enabled: bool,
    }

    pub async fn add_domain(
        axum::extract::State(db): axum::extract::State<Surreal<Any>>,
        Path(id): Path<String>,
        Json(domain_req): Json<DomainRequest>,
    ) -> Result<Json<Tenant>, Error> {
        // Validate domain format
        if !is_valid_domain(&domain_req.domain) {
            return Err(Error::BadRequest("Invalid domain format".to_string()));
        }
        
        // Check if domain already exists for another tenant
        let domain_check: Option<Tenant> = db
            .query("SELECT * FROM tenant WHERE domain = $domain")
            .bind(("domain", &domain_req.domain))
            .await?
            .take(0)?;
        
        if let Some(tenant) = domain_check {
            if tenant.id != id {
                return Err(Error::Conflict("Domain already in use".to_string()));
            }
        }
        
        // Update tenant with domain
        let tenant: Option<Tenant> = db
            .update(("tenant", &id))
            .merge(serde_json::json!({
                "domain": domain_req.domain,
                "ssl_enabled": false  // Initially false until cert is provisioned
            }))
            .await?;
        
        match tenant {
            Some(tenant) => {
                // Trigger SSL certificate generation in a background task
                tokio::spawn(generate_ssl_certificate(tenant.clone()));
                Ok(Json(tenant))
            },
            None => Err(Error::NotFound),
        }
    }

    pub async fn remove_domain(
        axum::extract::State(db): axum::extract::State<Surreal<Any>>,
        Path(id): Path<String>,
    ) -> Result<Json<Tenant>, Error> {
        // Update tenant to remove domain
        let tenant: Option<Tenant> = db
            .update(("tenant", &id))
            .merge(serde_json::json!({
                "domain": null,
                "ssl_enabled": null
            }))
            .await?;
        
        match tenant {
            Some(tenant) => Ok(Json(tenant)),
            None => Err(Error::NotFound),
        }
    }

    pub async fn list_domains(
        axum::extract::State(db): axum::extract::State<Surreal<Any>>,
    ) -> Result<Json<Vec<DomainInfo>>, Error> {
        let domains: Vec<DomainInfo> = db
            .query("SELECT id as tenant_id, domain, ssl_enabled FROM tenant WHERE domain IS NOT NULL")
            .await?
            .take(0)?;
        
        Ok(Json(domains))
    }

    // Helper function to validate domain format
    fn is_valid_domain(domain: &str) -> bool {
        // Basic domain validation regex
        // This is a simplified version - consider using a more robust validator
        let domain_regex = regex::Regex::new(r"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$").unwrap();
        domain_regex.is_match(domain)
    }

    // Background task to generate SSL certificate
    async fn generate_ssl_certificate(tenant: Tenant) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // Skip if no domain or already has SSL
        if tenant.domain.is_none() || tenant.ssl_enabled.unwrap_or(false) {
            return Ok(());
        }
        
        let domain = tenant.domain.as_ref().unwrap();
        
        // TODO: Implement actual Let's Encrypt certificate generation logic
        // This could be done by:
        // 1. Calling a separate service that manages certificates
        // 2. Using the ACME protocol directly
        // 3. Triggering a webhook that alerts Nginx to generate a cert
        
        // For now, simulate a successful certificate generation
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
        
        // Update tenant with SSL status
        let db = Surreal::connect("your-db-connection-string").await?;
        // Sign in and use the right namespace/db
        
        db.update(("tenant", &tenant.id))
            .merge(serde_json::json!({ "ssl_enabled": true }))
            .await?;
        
        println!("SSL certificate generated for domain: {}", domain);
        
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Load configuration based on environment
    let config = if let Ok(env_type) = env::var("ENVIRONMENT_TYPE") {
        match env_type.as_str() {
            "kubernetes" => {
                println!("Running in Kubernetes, loading secrets from mounted files");
                Config::from_k8s_secrets()?
            },
            "vault" => {
                println!("Loading secrets from Vault");
                Config::from_vault().await?
            },
            _ => {
                println!("Loading configuration from environment variables");
                Config::from_env()?
            }
        }
    } else {
        println!("No ENVIRONMENT_TYPE set, defaulting to environment variables");
        dotenv().ok();  // Load .env file if available
        Config::from_env()?
    };
    
    println!("Connecting to SurrealDB at {}", config.surrealdb_url);
    
    // Initialize database connection
    let db = any::connect(&config.surrealdb_url).await?;
    
    // Sign in
    db.signin(Root {
        username: &config.surrealdb_user,
        password: &config.surrealdb_pass,
    }).await?;
    
    // Select namespace and database
    db.use_ns(&config.surrealdb_ns).use_db(&config.surrealdb_db).await?;
    
    // Define schema
    db.query(
        "
        DEFINE TABLE IF NOT EXISTS tenant SCHEMALESS;
        DEFINE FIELD IF NOT EXISTS id ON TABLE tenant TYPE string;
        DEFINE FIELD IF NOT EXISTS name ON TABLE tenant TYPE string;
        DEFINE FIELD IF NOT EXISTS domain ON TABLE tenant TYPE string;
        DEFINE FIELD IF NOT EXISTS ssl_enabled ON TABLE tenant TYPE bool;
        DEFINE INDEX IF NOT EXISTS unique_tenant_id ON TABLE tenant FIELDS id UNIQUE;
        DEFINE INDEX IF NOT EXISTS unique_domain ON TABLE tenant FIELDS domain UNIQUE;
        "
    ).await?;
    
    println!("Connected to database successfully");
    
    // Create the router
    let router = Router::new()
        .route("/", get(routes::api_docs))
        .route("/tenants", get(routes::list_tenants))
        .route("/tenants/:id", post(routes::create_tenant))
        .route("/tenants/:id", get(routes::get_tenant))
        .route("/tenants/:id", put(routes::update_tenant))
        .route("/tenants/:id", delete(routes::delete_tenant))
        .route("/tenants/:id/domain", post(routes::add_domain))
        .route("/tenants/:id/domain", delete(routes::remove_domain))
        .route("/domains", get(routes::list_domains))
        .layer(CorsLayer::permissive())
        .with_state(db);
    
    // Start the server
    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    println!("Server running on {}", addr);
    
    let listener = TcpListener::bind(addr).await?;
    axum::serve(listener, router).await?;
    
    Ok(())
}