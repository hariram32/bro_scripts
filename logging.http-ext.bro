@load global-ext
@load http-ext

module HTTP;

export {
	# If set to T, this will split inbound and outbound transactions
	# into separate files.  F merges everything into a single file.
	const split_log_file = T &redef;
	
	# Which http transactions to log.
	# Choices are: Inbound, Outbound, All
	const logging = All &redef;
	
	# This is list of subnets containing web servers that you'd like to log their
	# traffic regardless of the "logging" variable.
	# The string value is a description of the subnet and why it was included.
	const always_log: table[subnet] of string &redef;
}

event bro_init()
	{
	LOG::create_logs("http-ext", logging, split_log_file, T);
	LOG::define_header("http-ext", cat_sep("\t", "\\N",
	                                       "ts",
	                                       "orig_h", "orig_p",
	                                       "resp_h", "resp_p",
	                                       "method", "url", "referrer",
	                                       "user_agent", "proxied_for",
	                                       "force_log_reasons"));
	
	# Set this log to always accept output because the POST logging
	# must be specifically enabled per-request anyway.
	LOG::create_logs("http-client-body", All, split_log_file, T);
	LOG::define_header("http-client-body", cat_sep("\t", "\\N",
	                                             "ts",
	                                             "orig_h", "orig_p",
	                                             "resp_h", "resp_p",
	                                             "url", "user_agent", "referrer",
	                                             "client_body"));
	}

event http_ext(id: conn_id, si: http_ext_session_info)
	{
	if ( id$resp_h in always_log )
		{
		si$force_log = T;
		add si$force_log_reasons[fmt("server_in_logged_subnet_%s", always_log[id$resp_h])];
		}

	local log = LOG::get_file("http-ext", id$resp_h, si$force_log);
	print log, cat_sep("\t", "\\N",
	                   si$start_time,
	                   id$orig_h, port_to_count(id$orig_p),
	                   id$resp_h, port_to_count(id$resp_p),
	                   si$method, si$url, si$referrer,
	                   si$user_agent, si$proxied_for,
	                   fmt_str_set(si$force_log_reasons, /DONTMATCH/));
	}

# This is coming, I just need to figure out to get get_file to
# accept either a Hosts enum value or a Directions enum value.
#event http_ext(id: conn_id, si: http_ext_session_info)
#	{
#	local log = LOG::get_file("http-ext-user-agents", id$orig_h, T);
#	print log, cat_sep("\t", "\\N", id$orig_h, si$user_agent);
#	}

# This is for logging POST contents during suspicious POSTs.
event http_entity_data(c: connection, is_orig: bool, length: count, data: string)
	{
	if ( !is_orig ) return;

	local ci = HTTP::conn_info[c$id];
	
	# This shouldn't really be done in the logging script, but it avoids
	# needing to handle the http_entity_data event twice.
	if ( suspicious_http_posts in data )
		{
		ci$force_log_client_body = T;
		add ci$force_log_reasons["suspicious_client_body"];
		}

	if ( ci$force_log_client_body )
		{
		local log = LOG::get_file("http-client-body", c$id$resp_h, T);
		print log, cat_sep("\t", "\\N",
		                   ci$start_time,
		                   c$id$orig_h, port_to_count(c$id$orig_p),
		                   c$id$resp_h, port_to_count(c$id$resp_p),
		                   ci$url,
		                   ci$user_agent,
		                   ci$referrer,
		                   data);
		}
	}