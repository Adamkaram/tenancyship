local ssl_automation = {}
local tenant_domains = ngx.shared.tenant_domains

local acme_client = require "resty.acme.client"
local acme_autossl = require "resty.acme.autossl"
local acme_storage = require "resty.acme.storage.redis"

function ssl_automation.init()
    -- Configure ACME client with Let's Encrypt
    local client = acme_client:new({
        directory_url = "https://acme-v02.api.letsencrypt.org/directory",
        account_key = "/etc/nginx/ssl/account.key",
        account_email = "admin@example.com",
        storage_adapter = acme_storage:new({
            host = "redis",
            port = 6379,
            database = 0,
            key_prefix = "letsencrypt:"
        })
    })

    -- Init Auto SSL
    ssl_automation.autossl = acme_autossl:new({
        client = client,
        domain_key_paths = {
            "/etc/nginx/ssl/domain.key"
        },
        storage_adapter = client.storage_adapter
    })
    
    ngx.log(ngx.INFO, "SSL automation initialized")
end

function ssl_automation.get_certificate()
    local domain = ngx.var.host
    
    -- Skip localhost and IP addresses
    if domain == "localhost" or domain:match("^%d+%.%d+%.%d+%.%d+$") then
        return
    end
    
    -- Check if domain is registered in our system
    local tenant_id = tenant_domains:get(domain)
    if not tenant_id then
        ngx.log(ngx.ERR, "Domain not registered: ", domain)
        return
    end
    
    -- Get or issue certificate
    local ok, err = ssl_automation.autossl:serve_certificate(domain)
    if not ok then
        ngx.log(ngx.ERR, "Failed to serve certificate for ", domain, ": ", err)
    end
end

function ssl_automation.serve_challenge()
    ssl_automation.autossl:serve_http_challenge()
end

return ssl_automation 