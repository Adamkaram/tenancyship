use actix_web::{web, App, HttpResponse, HttpServer};
use serde::{Deserialize, Serialize};
use surrealdb::engine::remote::ws::{Client, Ws};
use surrealdb::opt::auth::Root;
use surrealdb::{Result, Surreal};

#[derive(Debug, Serialize, Deserialize)]
struct Tenant {
    id: String,
    name: String,
}

struct AppState {
    db: Surreal<Client>,
}

async fn init_db() -> Result<Surreal<Client>> {
    let db = Surreal::new::<Ws>("surrealdb:8000").await?;
    
    // Configure authentication
    db.signin(Root {
        username: "root",
        password: "root",
    })
    .await?;

    // Select namespace and database
    db.use_ns("test").use_db("test").await?;
    
    Ok(db)
}

#[actix_web::post("/tenants")]
async fn create_tenant(
    state: web::Data<AppState>,
    tenant: web::Json<Tenant>,
) -> HttpResponse {
    let result = state
        .db
        .create(("tenant", &tenant.id))
        .content(tenant.0)
        .await;

    match result {
        Ok(_) => HttpResponse::Ok().json(tenant.0),
        Err(e) => HttpResponse::InternalServerError().body(e.to_string()),
    }
}

#[actix_web::get("/tenants")]
async fn list_tenants(state: web::Data<AppState>) -> HttpResponse {
    let result: Result<Vec<Tenant>> = state
        .db
        .select("tenant")
        .await;

    match result {
        Ok(tenants) => HttpResponse::Ok().json(tenants),
        Err(e) => HttpResponse::InternalServerError().body(e.to_string()),
    }
}

#[actix_web::get("/tenants/{id}")]
async fn get_tenant(
    state: web::Data<AppState>,
    id: web::Path<String>,
) -> HttpResponse {
    let result: Result<Option<Tenant>> = state
        .db
        .select(("tenant", id.as_str()))
        .await;

    match result {
        Ok(Some(tenant)) => HttpResponse::Ok().json(tenant),
        Ok(None) => HttpResponse::NotFound().finish(),
        Err(e) => HttpResponse::InternalServerError().body(e.to_string()),
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let db = init_db().await.expect("Failed to initialize database");
    let state = web::Data::new(AppState { db });

    HttpServer::new(move || {
        App::new()
            .app_data(state.clone())
            .service(create_tenant)
            .service(list_tenants)
            .service(get_tenant)
    })
    .bind("0.0.0.0:8080")?
    .run()
    .await
} 