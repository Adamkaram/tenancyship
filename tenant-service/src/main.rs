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
    }

    impl fmt::Display for Error {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            match self {
                Error::Db => write!(f, "database error"),
                Error::NotFound => write!(f, "not found"),
            }
        }
    }

    impl IntoResponse for Error {
        fn into_response(self) -> Response {
            let status = match self {
                Self::Db => StatusCode::INTERNAL_SERVER_ERROR,
                Self::NotFound => StatusCode::NOT_FOUND,
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
        DEFINE INDEX IF NOT EXISTS unique_tenant_id ON TABLE tenant FIELDS id UNIQUE;
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
        .layer(CorsLayer::permissive())
        .with_state(db);
    
    // Start the server
    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    println!("Server running on {}", addr);
    
    let listener = TcpListener::bind(addr).await?;
    axum::serve(listener, router).await?;
    
    Ok(())
}