#!/usr/bin/perl
use CGI qw/:standard/;
use func_common;
use func_apache;
use func_bind;
use func_html;
our $cgi= new CGI;
our %in=$cgi->Vars;

print "Content-type: text/html\n\n";

our %CONFIG;
our $server_root;
our $httpd_conf;
our %file_cache;
our $bind_base_dir;
&read_conf;

@pages_without_html_headers = ();

$bind_base_dir=&bind::get_base_directory($bind_conf);

$httpd_conf=&apache::get_config();
$bind_conf=&bind::get_config();

@info=();
if(url_param('action')){
    if(url_param('action') eq 'save_basic'){
	if(param('admin_email')=~/^.+?@.+$/ and length(param('server_root'))){
	    $serv_root=param('server_root');
	    $serv_root=~s/\/$//;
	    
	    &apache::save_directive("ServerAdmin", ['"' . param('admin_email') . '"'], $httpd_conf, $httpd_conf);
	    &apache::save_directive("DocumentRoot", ["\"$serv_root\""], $httpd_conf, $httpd_conf);
	    
	    &save_files();
	    
	    if(!system($CONFIG{'APACHE_RELOAD_COMMAND'}) && !system($CONFIG{'BIND_RELOAD_COMMAND'})){
		push(@info, "Settings successfuly saved");
	    }
	}
	else{
	    error("Incorrect input parameters");
	}
    }
    elsif(url_param('action') eq 'add_subdomain'){
	$name=param('name');
	$root=param('root');
	$domain=param('domain');
	if($name eq ''){
	    error("You have to fill 'Subdomain name' field!");
	}
	if(!$name=~/^\D([\w\d])*$/){
	    error("Please enter valid subdomain name!");
	}
	if($root eq ''){
	    error("You have to fill 'Subdomain root directory' field!");
	}
	if($domain eq ''){
	    error("You have to choose appropriate root domain!");
	}
	
	$sub_name="$name.$domain";
	@virts = &apache::find_directive_struct("VirtualHost", $httpd_conf);
	foreach $v (@virts) {
	    foreach $m (@{$v->{members}}){
		if($m->{name} eq "ServerName" && $m->{value} eq $sub_name){
		    error("Subdomain with name '$sub_name' already exists!");
		}
	    }
	}

	if ($root && !-d $root) {
	    mkdir($root, 0755) || error("Cannot create directory: $!");
	    $user = &apache::find_directive("User",$httpd_conf);
	    $group = &apache::find_directive("Group",$httpd_conf);
	    $uid = $user ? getpwnam($user) : 0;
	    $gid = $group ? getgrnam($group) : 0;
	    chown($uid, $gid, $root);
	}

	if($#virts){
	    $file_to_add=$virts[$#virts]->{'file'};
	}
	else{
	    $file_to_add=$CONFIG{'APACHE_CONF_PATH'};
	}

	@nvhosts=&apache::find_directive("NameVirtualHost",$httpd_conf);
	if(!in_array("*:80",@nvhosts)){
	    &apache::save_directive("NameVirtualHost", [ @nvhosts, "*:80" ], $httpd_conf, $httpd_conf);
	}

	@mems = ( );
	$virt = { 'name' => 'VirtualHost',
		  'value' => "*:80",
		  'file' => $file_to_add,
		  'type' => 1,
		  'members' => \@mems
		};
	push(@mems, { 'name' => 'DocumentRoot', 'value' => "\"$root\"" } );
	push(@mems, { 'name' => 'ServerName', 'value' => $sub_name } );
	push(@mems, {
		      'name' => 'Directory',
		      'value' => "\"$root\"",
		      'type' => 1,
		      'members' => [
					{ 'name' => 'Order', 'value' => 'Deny,Allow' },
					{ 'name' => 'Allow', 'value' => 'from all' },
					{ 'name' => 'Options', 'value' => '+Indexes' },
				    ]
		    }
	    );
	&apache::save_directive_struct(undef, $virt, $httpd_conf, $httpd_conf);
	
	# Find zone file to save
	$zone_file='';
	$origin='';
	@zones=&bind::find("zone", $bind_conf);
	foreach $zone (@zones){
	    $zval=$zone->{'value'};
	    if("$domain."=~/$zval$/ and $zval ne "."){
		$zone_file=&bind::find("file", $zone->{'members'})->{'value'};
		$origin=$zval;
		last;
	    }
	}
	if(!$zone_file){
	    error("There is no '$domain.' zone!");
	}
	$named_root=&bind::find("directory", &bind::find("options", $bind_conf)->{'members'})->{'value'};
	$named_root=~s/\/$//;
	$zone_file=$named_root . '/' . $zone_file;
	$origin=~s/\.$//;
	$zone_conf=&bind::read_zone_file($zone_file, $origin);
	
	$subdomain_add_part = substr($sub_name, 0, index($sub_name,$origin)-1);
	
	$dom=&bind::find($sub_name . ".", $zone_conf);
	if(!$dom){
	    &bind::create_record($zone_file, $subdomain_add_part, "", "IN", "A", $CONFIG{'SERVER_MAIN_IP'}, "Subdomain $sub_name");
	}
	
	&save_files();
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'}) && !system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly added subdomain $sub_name");
	}
    }
    elsif(url_param('action') eq 'del_subdomain'){
	if(!url_param('id')=~/^\d+$/){
	    error("There is no ID to delete!");
	}
	@vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
	$domain=&html::strip_quotes(&apache::find_directive("ServerName", $vhosts[url_param('id')]->{'members'}));
	&apache::save_directive_struct($vhosts[url_param('id')], undef, $httpd_conf, $httpd_conf);
	
	$zone_file='';
	$origin='';
	@zones=&bind::find("zone", $bind_conf);
	foreach $zone (@zones){
	    $zval=$zone->{'value'};
	    if("$domain."=~/$zval$/ and $zval ne "."){
		$zone_file=&bind::find("file", $zone->{'members'})->{'value'};
		$origin=$zval;
		last;
	    }
	}
	if(!$zone_file){
	    error("There is no '$domain.' zone!");
	}
	$named_root=&bind::find("directory", &bind::find("options", $bind_conf)->{'members'})->{'value'};
	$named_root=~s/\/$//;
	$zone_file=$named_root . '/' . $zone_file;
	$origin=~s/\.$//;
	$zone_conf=&bind::read_zone_file($zone_file, $origin);
	
	&bind::delete_record($zone_file , &bind::find("$domain.",$zone_conf));
	
	&save_files();
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'}) && !system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly deleted subdomain $domain");
	}
    }
    elsif(url_param('action') eq 'add_domain'){
	$name=param('name');
	$root=param('root');
	if($name eq ''){
	    error("You have to fill 'Domain name' field!");
	}
	@level=split(/\./,$name);
	if($#level!=1){
	    error("Domain has to be a second level domain (e.g. example.com)!");
	}
	if(!$name=~/^\D([\w\d])*\.\w+$/){
	    error("Please enter valid domain name!");
	}
	if($root eq ''){
	    error("You have to fill 'Domain root directory' field!");
	}
	
	@virts = &apache::find_directive_struct("VirtualHost", $httpd_conf);
	foreach $v (@virts) {
	    foreach $m (@{$v->{members}}){
		if($m->{name} eq "ServerName" && $m->{value} eq $name){
		    error("Domain with name '$name' already exists!");
		}
	    }
	}

	if ($root && !-d $root) {
	    mkdir($root, 0755) || error("Cannot create directory: $!");
	    $user = &apache::find_directive("User",$httpd_conf);
	    $group = &apache::find_directive("Group",$httpd_conf);
	    $uid = $user ? getpwnam($user) : 0;
	    $gid = $group ? getgrnam($group) : 0;
	    chown($uid, $gid, $root);
	}

	if($#virts){
	    $file_to_add=$virts[$#virts]->{'file'};
	}
	else{
	    $file_to_add=$CONFIG{'APACHE_CONF_PATH'};
	}

	@nvhosts=&apache::find_directive("NameVirtualHost",$httpd_conf);
	if(!in_array("*:80",@nvhosts)){
	    &apache::save_directive("NameVirtualHost", [ @nvhosts, "*:80" ], $httpd_conf, $httpd_conf);
	}

	@mems = ( );
	$virt = { 'name' => 'VirtualHost',
		  'value' => "*:80",
		  'file' => $file_to_add,
		  'type' => 1,
		  'members' => \@mems
		};
	push(@mems, { 'name' => 'DocumentRoot', 'value' => "\"$root\"" } );
	push(@mems, { 'name' => 'ServerName', 'value' => $name } );
	push(@mems, { 'name' => 'ServerAlias', 'value' => "www.$name" } );
	push(@mems, {
		      'name' => 'Directory',
		      'value' => "\"$root\"",
		      'type' => 1,
		      'members' => [
					{ 'name' => 'Order', 'value' => 'Deny,Allow' },
					{ 'name' => 'Allow', 'value' => 'from all' },
					{ 'name' => 'Options', 'value' => '+Indexes' },
				    ]
		    }
	    );
	&apache::save_directive_struct(undef, $virt, $httpd_conf, $httpd_conf);
	
	
	$records_file = $name.".db";
	$dir = { 'name' => 'zone',
	 'values' => [ '"' . $name . '."' ],
	 'type' => 1,
	 'members' => [ { 'name' => 'type',
			  'values' => [ 'master' ] },
			{ 'name' => 'file',
			  'values' => [ '"' . $records_file . '"' ] } ]
	};
	
	&bind::create_zone($dir, $bind_conf);
	
	$named_root=&bind::find("directory", &bind::find("options", $bind_conf)->{'members'})->{'value'};
	$named_root=~s/\/$//;
	$zone_file=$named_root . '/' . $records_file;
	
	local $vals = $CONFIG{'SERVER_HOSTNAME'} . ". ".&bind::email_to_dotted($CONFIG{'SERVER_EMAIL'})." (\n".
        "\t\t\t".time()."\n".
        "\t\t\t10800\n".
        "\t\t\t3600\n".
        "\t\t\t604800\n".
        "\t\t\t38400 )";
	
	$file_without_slash=$zone_file;
	$file_without_slash=~s/^\///;
	open(ZONE, ">".$CONFIG{'BIND_CHROOT'} . $file_without_slash);
	print ZONE "\$ttl 38400\n";
	close(ZONE);

	&bind::create_record($zone_file, "$name.", undef, "IN", "SOA", $vals);
	&bind::create_record($zone_file, "$name.", undef, "IN", "NS", $CONFIG{'SERVER_HOSTNAME'})
	&bind::create_record($zone_file, "$name.", undef, "IN", "A", $CONFIG{'SERVER_MAIN_IP'}, "Domain $name");
	&bind::create_record($zone_file, 'www', undef, "IN", "CNAME", $name . '.', "CNAME for $name");
	
	&save_files();
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'}) && !system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly added domain $name");
	}
    }
    elsif(url_param('action') eq 'del_domain'){
	if(!length(url_param('id'))){
	    error("There is no ID to delete!");
	}
	@vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
	$domain=&html::strip_quotes(&apache::find_directive("ServerName", $vhosts[url_param('id')]->{'members'}));
	&apache::save_directive_struct($vhosts[url_param('id')], undef, $httpd_conf, $httpd_conf);
	foreach $vhost (@vhosts){
	    $vh_domain=&html::strip_quotes(&apache::find_directive("ServerName", $vhost->{'members'}));
	    if($vh_domain =~ /\.$domain$/){
		&apache::save_directive_struct($vhost, undef, $httpd_conf, $httpd_conf);
	    }
	}
	
	$zone_file='';
	$origin='';
	@zones=&bind::find("zone", $bind_conf);
	foreach $zone (@zones){
	    $zval=$zone->{'value'};
	    if("$domain."=~/$zval$/ and $zval ne "."){
		$zone_file=&bind::find("file", $zone->{'members'})->{'value'};
		&bind::save_directive(&bind::get_config_parent(), [ $zone ], undef, 0);
		last;
	    }
	}
	if(!$zone_file){
	    error("There is no '$domain.' zone!");
	}
	$named_root=&bind::find("directory", &bind::find("options", $bind_conf)->{'members'})->{'value'};
	$named_root=~s/\/$//;
	$named_root=~s/^\///;
	$zone_file=$named_root . '/' . $zone_file;

	unlink($CONFIG{'BIND_CHROOT'} . $zone_file);
	
	&save_files();
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'}) && !system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly deleted domain $domain");
	}
    }
    elsif(url_param('action') eq 'save_access'){
	$allow_list=param('allow_list');
	$deny_list=param('deny_list');
	$order=param('order');
	if($allow_list =~ /^all$/m or $deny_list =~ /^all$/m){
	    error("Allow and deny lists must not contain 'all' words");
	}
	@vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
	$vhost=$vhosts[url_param('id')];
	$domain=&apache::find_directive("ServerName", $vhost->{'members'});
	$directory=&apache::find_directive_struct("Directory", $vhost->{'members'});
	if($order eq 'ad'){
	    $order="Allow,Deny";
	}
	else{
	    $order="Deny,Allow";
	}
	&apache::save_directive("Order", [$order], $directory->{'members'}, $httpd_conf);
	$allows=split_by_nl($allow_list);
	$denys=split_by_nl($deny_list);
	$allow_list=join(" ", @$allows);
	$deny_list=join(" ", @$denys);
	if(length(@$allows)==-1 && length(@$denys)==-1){
	    if(param('order') eq 'da'){
		&apache::save_directive("Allow", [], $directory->{'members'}, $httpd_conf);
		&apache::save_directive("Deny", ["from all"], $directory->{'members'}, $httpd_conf);
	    }
	    else{
		&apache::save_directive("Allow", ["from all"], $directory->{'members'}, $httpd_conf);
		&apache::save_directive("Deny", [], $directory->{'members'}, $httpd_conf);
	    }
	}
	else{
	    if(param('order') eq 'da'){
		&apache::save_directive("Deny", ["from all"], $directory->{'members'}, $httpd_conf);
		if(length($allow_list)){
		    &apache::save_directive("Allow", ["from $allow_list"], $directory->{'members'}, $httpd_conf);
		}
		else{
		    &apache::save_directive("Allow", [], $directory->{'members'}, $httpd_conf);
		}
	    }
	    else{
		&apache::save_directive("Allow", ["from all"], $directory->{'members'}, $httpd_conf);
		if(length($deny_list)){
		    &apache::save_directive("Deny", ["from $deny_list"], $directory->{'members'}, $httpd_conf);
		}
		else{
		    &apache::save_directive("Deny", [], $directory->{'members'}, $httpd_conf);
		}
	    }
	}
	
	&save_files();
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'}) && !system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly save access information for domain $domain");
	}
    }
    elsif(url_param('action') eq 'save_adv_basic_settings'){
	if(!param('admin_email')=~/^.+?@.+$/){
	    error("Incorrect input parameters");
	}
	if(!-d param('server_root')){
	    error("Please enter valid server root directory");
	}
	if(!length(param('user'))){
	    error("Please enter valid user for apache");
	}
	if(!length(param('group'))){
	    error("Please enter valid group for apache");
	}
	if(!length(param('server_name'))){
	    error("Please enter valid server name for apache");
	}
	if(!length(param('listen'))){
	    error("Please at least one port for server to listen");
	}
	$serv_root=param('server_root');
	$serv_root=~s/\/$//;
	
	&apache::save_directive("ServerAdmin", ['"' . param('admin_email') . '"'], $httpd_conf, $httpd_conf);
	&apache::save_directive("DocumentRoot", ['"' . $serv_root . '"'], $httpd_conf, $httpd_conf);
	&apache::save_directive("ServerName", ['"' .param('server_name') . '"'], $httpd_conf, $httpd_conf);
	&apache::save_directive("Listen", split_by_nl(param('listen')), $httpd_conf, $httpd_conf);
	&apache::save_directive("NameVirtualHost", split_by_nl(param('nvhosts')), $httpd_conf, $httpd_conf);
	
	&apache::save_directive("Timeout", (length(param('req_tmout')) ? [param('req_tmout')] : undef), $httpd_conf, $httpd_conf);
	&apache::save_directive("KeepAliveTimeout", (length(param('kpalive_tmout')) ? [param('kpalive_tmout')] : undef), $httpd_conf, $httpd_conf);
	&apache::save_directive("LimitRequestFields", (length(param('LimitRequestFields')) ? [param('LimitRequestFields')] : undef), $httpd_conf, $httpd_conf);
	&apache::save_directive("LimitRequestLine", (length(param('LimitRequestLine')) ? [param('LimitRequestLine')] : undef), $httpd_conf, $httpd_conf);
	&apache::save_directive("MaxRequestsPerChild", (length(param('MaxRequestsPerChild')) ? [param('MaxRequestsPerChild')] : undef), $httpd_conf, $httpd_conf);
	&apache::save_directive("LimitRequestFieldsize", (length(param('LimitRequestFieldsize')) ? [param('LimitRequestFieldsize')] : undef), $httpd_conf, $httpd_conf);
	&apache::save_directive("SendBufferSize", (length(param('SendBufferSize')) ? [param('SendBufferSize')] : undef), $httpd_conf, $httpd_conf);
	&apache::save_directive("ListenBacklog", (length(param('ListenBacklog')) ? [param('ListenBacklog')] : undef), $httpd_conf, $httpd_conf);
	
	&apache::save_directive("User", [param('user')], $httpd_conf, $httpd_conf);
	&apache::save_directive("Group", [param('group')], $httpd_conf, $httpd_conf);
	
	&save_files();
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'}) && !system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly saved settings");
	}
    }
    elsif(url_param('action') eq 'add_vhost'){
	$name=param('name');
	$root=param('root');
	$listen_addr=param('listen_addr');
	$listen_port=param('listen_port');
	$aliases=split_by_nl(param('aliases'));
	if($name eq ''){
	    error("You have to fill 'Domain name' field!");
	}
	if(!$name=~/^\D([\w\d])*\.\w+$/){
	    error("Please enter valid domain name!");
	}
	if($root eq ''){
	    error("You have to fill 'Domain root directory' field!");
	}
	if($listen_addr eq '' or $listen_port eq ''){
	    error("You have to specify valid listen address and port!");
	}
	
	$listen="$listen_addr:$listen_port";
	
	@virts = &apache::find_directive_struct("VirtualHost", $httpd_conf);
	foreach $v (@virts) {
	    foreach $m (@{$v->{members}}){
		if($m->{name} eq "ServerName" && $m->{value} eq $name){
		    error("Virtual host with name '$name' already exists!");
		}
	    }
	}
	
	if ($root && !-d $root) {
	    mkdir($root, 0755) || error("Cannot create directory: $!");
	    $user = &apache::find_directive("User",$httpd_conf);
	    $group = &apache::find_directive("Group",$httpd_conf);
	    $uid = $user ? getpwnam($user) : 0;
	    $gid = $group ? getgrnam($group) : 0;
	    chown($uid, $gid, $root);
	}

	if($#virts){
	    $file_to_add=$virts[$#virts]->{'file'};
	}
	else{
	    $file_to_add=$CONFIG{'APACHE_CONF_PATH'};
	}

	@nvhosts=&apache::find_directive("NameVirtualHost",$httpd_conf);
	if(!in_array($listen,@nvhosts)){
	    &apache::save_directive("NameVirtualHost", [ @nvhosts, $listen ], $httpd_conf, $httpd_conf);
	}
	
	@listens=&apache::find_directive("Listen",$httpd_conf);
	if(!in_array($listen_port,@listens)){
	    &apache::save_directive("Listen", [ @nvhosts, $listen_port ], $httpd_conf, $httpd_conf);
	}

	@mems = ( );
	$virt = { 'name' => 'VirtualHost',
		  'value' => $listen,
		  'file' => $file_to_add,
		  'type' => 1,
		  'members' => \@mems
		};
	push(@mems, { 'name' => 'DocumentRoot', 'value' => "\"$root\"" } );
	push(@mems, { 'name' => 'ServerName', 'value' => $name } );
	foreach (@$aliases){
	    push(@mems, { 'name' => 'ServerAlias', 'value' => $_ } );
	}
	push(@mems, {
		      'name' => 'Directory',
		      'value' => "\"$root\"",
		      'type' => 1,
		      'members' => [
					{ 'name' => 'Order', 'value' => 'Deny,Allow' },
					{ 'name' => 'Allow', 'value' => 'from all' },
					{ 'name' => 'Options', 'value' => '+Indexes' },
				    ]
		    }
	    );
	&apache::save_directive_struct(undef, $virt, $httpd_conf, $httpd_conf);
	
	&save_files();
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'})){
	    push(@info, "Successfuly added virtual host $name");
	}
    }
    elsif(url_param('action') eq 'del_vhost'){
	if(!url_param('id')=~/^\d+$/){
	    error("There is no ID to delete!");
	}
	@vhosts=&apache::find_directive_struct("VirtualHost",$httpd_conf);
	$domain=&html::strip_quotes(&apache::find_directive("ServerName", $vhosts[url_param('id')]->{'members'}));
	&apache::save_directive_struct($vhosts[url_param('id')], undef, $httpd_conf, $httpd_conf);
	
	&save_files();
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'})){
	    push(@info, "Successfuly deleted virtual host $domain");
	}
    }
    elsif(url_param('action') eq 'save_vhost'){
	$id = url_param('id');
	if(!$id){
	    error("Unable to save directives");
	}
	if(!length(param('ServerName'))){
	    error("Please enter valid server name for virtual host");
	}
	if(length (param('ServerAdmin')) and !param('ServerAdmin')=~/^.+?@.+$/){
	    error("Please enter valid administrator email");
	}
	if(!-d param('DocumentRoot')){
	    error("Please enter valid root directory");
	}
	
	@vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
	$vhost=$vhosts[$id]->{'members'};
	
	
	############     MAIN PART
	$serv_root=param('DocumentRoot');
	$serv_root=~s/\/$//;
	
	&apache::save_directive("ServerName", ['"' .param('ServerName') . '"'], $vhost, $httpd_conf);
	&apache::save_directive("ServerAdmin", (length(param('ServerAdmin')) ? [param('ServerAdmin')] : undef), $vhost, $httpd_conf);
	&apache::save_directive("DocumentRoot", ['"' . $serv_root . '"'], $vhost, $httpd_conf);
	&apache::save_directive("ServerAlias", split_by_nl(param('ServerAlias')), $vhost, $httpd_conf);
	
	
	############     Resource limits
	
	&apache::save_directive("LimitRequestBody", (length(param('LimitRequestBody')) ? [param('LimitRequestBody')] : undef), $vhost, $httpd_conf);
	&apache::save_directive("LimitXMLRequestBody", (length(param('LimitXMLRequestBody')) ? [param('LimitXMLRequestBody')] : undef), $vhost, $httpd_conf);
	if(length(param('RLimitCPU_0')) and length(param('RLimitCPU_1'))){
	    $val=param('RLimitCPU_0') . ' ' . param('RLimitCPU_1');
	    &apache::save_directive("RLimitCPU", [$val], $vhost, $httpd_conf);
	}
	else{
	    &apache::save_directive("RLimitCPU", undef, $vhost, $httpd_conf);
	}
	if(length(param('RLimitMEM_0')) and length(param('RLimitMEM_1'))){
	    $val=param('RLimitMEM_0') . ' ' . param('RLimitMEM_1');
	    &apache::save_directive("RLimitMEM", [$val], $vhost, $httpd_conf);
	}
	else{
	    &apache::save_directive("RLimitMEM", undef, $vhost, $httpd_conf);
	}
	if(length(param('RLimitNPROC_0')) and length(param('RLimitNPROC_1'))){
	    $val=param('RLimitNPROC_0') . ' ' . param('RLimitNPROC_1');
	    &apache::save_directive("RLimitNPROC", [$val], $vhost, $httpd_conf);
	}
	else{
	    &apache::save_directive("RLimitNPROC", undef, $vhost, $httpd_conf);
	}
	
	############     Logging
	
	&apache::save_directive("ErrorLog", (length(param('ErrorLog')) ? [param('ErrorLog')] : undef), $vhost, $httpd_conf);
	if(length(param('ErrorLog'))){
	    open(EL, ">" . $CONFIG{'APACHE_SERVER_ROOT'} .'/'. param('ErrorLog'));
	    close(EL);
	    &apache::save_directive("LogLevel", (length(param('warn_level')) ? [param('warn_level')] : undef), $vhost, $httpd_conf);
	}
	
	if(length(param('CustomLog'))){
	    &apache::save_directive("CustomLog", [param('CustomLog') . ' combined'], $vhost, $httpd_conf);
	    open(EL, ">" . $CONFIG{'APACHE_SERVER_ROOT'} .'/'. param('CustomLog'));
	    close(EL);
	}
	else{
	    &apache::save_directive("CustomLog", undef, $vhost, $httpd_conf);
	}
	############     User/Group
	
	if(length(param('user')) and length(param('group'))){
	    &apache::save_directive("SuexecUserGroup", [param('user') . ' ' . param('group')], $vhost, $httpd_conf);
	}
	else{
	    &apache::save_directive("SuexecUserGroup", undef, $vhost, $httpd_conf);
	}
	
	&save_files();
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'})){
	    push(@info, "Successfuly saved settings");
	}
    }
    elsif(url_param('action') eq 'add_zone'){
	if(
	   !length(param('name')) or
	   !length(param('master')) or
	   !length(param('email')) or
	   !length(param('refresh')) or
	   !length(param('expiry')) or
	   !length(param('transfer')) or
	   !length(param('cache'))
	   ){
	    error("All fields are mandatory!");
	}
	$name=param('name');
	$master=param("master");
	$email=param("email");
	$refresh=param("refresh").param("refunit");
	$expiry=param("expiry").param("expunit");
	$transfer=param("transfer").param("tranunit");
	$cache=param("cache").param("chahceunit");
	
	$records_file = $name.".db";
	$dir = { 'name' => 'zone',
	 'values' => [ '"' . $name . '."' ],
	 'type' => 1,
	 'members' => [ { 'name' => 'type',
			  'values' => [ 'master' ] },
			{ 'name' => 'file',
			  'values' => [ '"' . $records_file . '"' ] } ]
	};
	
	&bind::create_zone($dir, $bind_conf);
	
	$named_root=&bind::find("directory", &bind::find("options", $bind_conf)->{'members'})->{'value'};
	$named_root=~s/\/$//;
	$zone_file=$named_root . '/' . $records_file;
	
	local $vals = $master . ". ".&bind::email_to_dotted($email)." (\n".
        "\t\t\t".time()."\n".
        "\t\t\t$refresh\n".
        "\t\t\t$transfer\n".
        "\t\t\t$expiry\n".
        "\t\t\t$cache )";
	
	$file_without_slash=$zone_file;
	$file_without_slash=~s/^\///;
	open(ZONE, ">".$CONFIG{'BIND_CHROOT'} . $file_without_slash);
	print ZONE "\$ttl 38400\n";
	close(ZONE);

	&bind::create_record($zone_file, "$name.", undef, "IN", "SOA", $vals);
	&bind::create_record($zone_file, "$name.", undef, "IN", "NS", $master);
	
	if(length(param('ip'))){
	    &bind::create_record($zone_file, "$name.", undef, "IN", "A", param('ip'));
	}
	foreach $alias (@{split_by_nl(param('aliases'))}){
	    &bind::create_record($zone_file, $alias, undef, "IN", "CNAME", $name . '.');
	}
	
	&save_files();
	$bind_conf=&bind::get_config();
	
	if(!system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly added zone $name");
	}
    }
    elsif(url_param('action') eq 'del_zone'){
	if(!url_param('id')=~/^\d+$/){
	    error("There is no ID to delete!");
	}
	$zone_file='';
	$origin='';
	@zones=&bind::find("zone", $bind_conf);
	$domain=$zones[url_param('id')]->{'value'};
	$zone_file=&bind::find("file", $zones[url_param('id')]->{'members'})->{'value'};
	&bind::save_directive(&bind::get_config_parent(), [ $zones[url_param('id')] ], undef, 0);
	
	$named_root=&bind::find("directory", &bind::find("options", $bind_conf)->{'members'})->{'value'};
	$named_root=~s/\/$//;
	$named_root=~s/^\///;
	$zone_file=$named_root . '/' . $zone_file;

	unlink($CONFIG{'BIND_CHROOT'} . $zone_file);
	
	&save_files();
	$bind_conf=&bind::get_config();
	
	if(!system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly deleted zone $domain");
	}
    }
    elsif(url_param('action') eq 'save_zone'){
	if(!url_param('id')=~/^\d+$/){
	    error("There is no ID to save!");
	}
	$zone_file='';
	$origin='';
	@zones=&bind::find("zone", $bind_conf);
	$domain=$zones[url_param('id')]->{'value'};
	$zone_file=&bind::find("file", $zones[url_param('id')]->{'members'})->{'value'};
	
	$named_root=&bind::find("directory", &bind::find("options", $bind_conf)->{'members'})->{'value'};
	$named_root=~s/\/$//;
	$named_root=~s/^\///;
	$zone_file=$named_root . '/' . $zone_file;

	open (FL, ">".$CONFIG{'BIND_CHROOT'} . $zone_file) or error("Can't open file for writing: $!");
	print FL param('zone_file');
	close FL;
	
	&save_files();
	
	if(!system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly saved records file for zone $domain");
	}
    }
    elsif(url_param('action') eq 'save_apache'){
	unless(-f param('file')){
	    error("No such file!");
	}
	open (FL, ">".param('file')) or error("Can't open file for writing: $!");
	print FL param('text');
	close FL;
	
	if(!system($CONFIG{'APACHE_RELOAD_COMMAND'})){
	    push(@info, "Successfuly saved file " . param('file'));
	}
    }
    elsif(url_param('action') eq 'save_dns'){
	open (FL, ">".$CONFIG{'BIND_NAMED_CONF'}) or error("Can't open file for writing: $!");
	print FL param('text');
	close FL;
	
	if(!system($CONFIG{'BIND_RELOAD_COMMAND'})){
	    push(@info, "Successfuly saved file " . param('file'));
	}
    }
}

&html::get_header if(!grep(url_param('page'),@pages_without_html_headers));
if(@info){
    for(@info){
	print "<pre class=green>$_</pre>";
    }
}
if(url_param('page') ne ''){
    if(url_param('page') eq 'apache_simple'){
	&html::get_apache_simple();
    }
    elsif(url_param('page') eq 'basic_settings'){
	&html::get_basic_settings();
    }
    elsif(url_param('page') eq 'subdomains'){
	&html::get_subdomains();
    }
    elsif(url_param('page') eq 'domains'){
	&html::get_domains();
    }
    elsif(url_param('page') eq 'access'){
	&html::get_domains_for_access();
    }
    elsif(url_param('page') eq 'man_access'){
	&html::get_man_access(url_param('id'));
    }
    elsif(url_param('page') eq 'apache_adv'){
	&html::get_apache_adv();
    }
    elsif(url_param('page') eq 'adv_basic_settings'){
	&html::get_adv_basic_settings();
    }
    elsif(url_param('page') eq 'virt_hosts'){
	&html::get_virt_hosts();
    }
    elsif(url_param('page') eq 'edit_vhost'){
	&html::get_edit_vhost(url_param('vid'));
    }
    elsif(url_param('page') eq 'zones'){
	&html::get_zones();
    }
    elsif(url_param('page') eq 'edit_zone'){
	&html::get_edit_zone(url_param('id'));
    }
    elsif(url_param('page') eq 'edit_apache'){
	&html::get_edit_apache();
    }
    elsif(url_param('page') eq 'edit_dns'){
	&html::get_edit_dns();
    }
    
}
else{
    &html::get_apache_simple;
}
&html::get_footer() if(!grep(url_param('page'),@pages_without_html_headers));