use axum::{
    extract::Path,
    routing::{get, post, delete, put},
    Json, Router,
};
use dotenv::dotenv;
use serde::{Deserialize, Serialize};
use std::env;
use std::net::SocketAddr;
use surrealdb::engine::any::{self, Any};
use surrealdb::opt::auth::Root;
use surrealdb::Surreal;
use tokio::net::TcpListener;
use tower_http::cors::CorsLayer;

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
        // Ensure the ID in path matches the tenant ID
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
        // Ensure the ID stays the same
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
    dotenv().ok();
    
    // Get connection details from environment
    let db_url = env::var("SURREALDB_URL").expect("SURREALDB_URL must be set");
    let db_user = env::var("SURREALDB_USER").expect("SURREALDB_USER must be set");
    let db_pass = env::var("SURREALDB_PASS").expect("SURREALDB_PASS must be set");
    let db_ns = env::var("SURREALDB_NS").expect("SURREALDB_NS must be set");
    let db_db = env::var("SURREALDB_DB").expect("SURREALDB_DB must be set");
    
    println!("Connecting to SurrealDB at {}", db_url);
    
    // Open a connection using the "any" engine
    let db = any::connect(db_url).await?;
    
    // Sign in as root
    db.signin(Root {
        username: &db_user,
        password: &db_pass,
    }).await?;
    
    // Select namespace and database
    db.use_ns(db_ns).use_db(db_db).await?;
    
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