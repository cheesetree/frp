local cfg = require "comm.config"
local json = require "cjson"
local ngx_resp = require "ngx.resp"

local reqid = ngx.var.request_id
local head = ngx.req.get_headers()
ngx.req.read_body()
local body = ngx.req.get_body_data()

ngx.shared.frp_reqq:lpush(cfg.frp.server.reqq_name,reqid)
if body == nil then
    body = ""
end

ngx.shared.frp_reqq_data:safe_add(reqid,json.encode({
    ["type"]="req",
    ["content"]={["reqid"]=reqid,["body"]=body,["head"]=head,["method"]=ngx.req.get_method()}
}))

local tm = cfg.frp.server.timeout
while tm > 0 do
    local res = ngx.shared.frp_resq_data:get(reqid)
    if res then
        local resp = json.decode(res)
        ngx.shared.frp_resq_data:delete(reqid)
        if resp then
            if(resp["head"] and type(resp["head"] == "table")) then
                for key, value in pairs(resp["head"]) do
                    ngx_resp.add_header(key,value)
                end
            end

            ngx.status = resp["status"]
            ngx.print(resp["body"])
            ngx.exit(resp["status"])
        else
            ngx.exit(500)
        end
    end
    ngx.sleep(0.1)
    tm = tm - 0.1
end

ngx.exit(504)
