local tenant_resolver = {}
local tenant_domains = ngx.shared.tenant_domains
local http = require "resty.http"

-- This function will be called periodically to update domain cache
function tenant_resolver.update_domain_cache()
    local httpc = http.new()
    local res, err = httpc:request_uri("http://tenant-service:8080/domains", {
        method = "GET",
        headers = {
            ["Content-Type"] = "application/json"
        }
    })

    if not res then
        ngx.log(ngx.ERR, "Failed to fetch domains: ", err)
        return
    end

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "Failed to fetch domains, status: ", res.status)
        return
    end

    local domains = require("cjson").decode(res.body)
    
    -- Clear existing cache
    tenant_domains:flush_all()
    
    -- Update cache with new domains
    for _, domain_info in ipairs(domains) do
        tenant_domains:set(domain_info.domain, domain_info.tenant_id)
        ngx.log(ngx.INFO, "Cached domain mapping: ", domain_info.domain, " -> ", domain_info.tenant_id)
    end
end

-- Function to resolve tenant by domain
function tenant_resolver.resolve_tenant_by_domain(domain)
    return tenant_domains:get(domain)
end

-- Initialize the resolver and set up timer for cache updates
function tenant_resolver.init()
    -- Update cache immediately
    tenant_resolver.update_domain_cache()
    
    -- Schedule periodic updates (every 60 seconds)
    local ok, err = ngx.timer.every(60, tenant_resolver.update_domain_cache)
    if not ok then
        ngx.log(ngx.ERR, "Failed to create domain cache updater: ", err)
    end
end

return tenant_resolver 