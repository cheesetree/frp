local ngx_re = require "ngx.re"
local uri_args,err = ngx_re.split(ngx.var.document_uri,"/")

if not uri_args then
    ngx.log(ngx.ERR,"failed to split uri: ",err)
    ngx.exit(500)
end

if(uri_args and #(uri_args)>1) then
    local appid = uri_args[2]
    if (ngx.shared.frp_sys:get(appid) ~= nil) then
        ngx.log(ngx.ERR,"appid: ",appid," is already exist")
        ngx.exit(404)
    end
end