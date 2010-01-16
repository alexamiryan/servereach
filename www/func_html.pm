#!/usr/bin/perl
package html;

sub get_header{
    print <<EOF;
    <html>
    <head>
    <meta http-equiv="Content-Language" content="en" />
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <title>WSC - Web Server Configurator</title>
    <link rel="stylesheet" href="style.css" type="text/css">
    </head>
    <body> 
EOF
}

sub get_footer{
    print <<EOF;
    </body>
    </html>
EOF
}

sub get_menu{
    print <<EOF;
    <h2><a href="index.cgi?page=apache_simple" target="content">Apache</a></h2>
    <h2><a href="index.cgi?page=bind" target="content">BIND</a></h2>
EOF
}

sub get_apache_menu{
    print <<EOF;
    Modes: <a href="index.cgi?page=apache_simple">Simple</a> |
    <a href="index.cgi?page=apache_adv">Advanced</a>
    <hr>
EOF
}

sub get_apache_simple{
    &get_apache_menu;
    print <<EOF;
    <table cellpadding="5" cellspacing="2" summary="" width="300">
    	<tr>
    		<td><a href="index.cgi?page=basic_settings">Server Basic Settings</a></td>
    	</tr>
    	<tr>
    		<td><a href="index.cgi?page=domains">Domains</a></td>
    	</tr>
    	<tr>
    		<td><a href="index.cgi?page=subdomains">Sub Domains</a></td>
    	</tr>
    	<tr>
    		<td><a href="index.cgi?page=access">Restrict access</a></td>
    	</tr>
    </table>
EOF
}

sub get_apache_adv{
    &get_apache_menu;
    print <<EOF;
    <table cellpadding="5" cellspacing="2" summary="" width="300">
    	<tr>
    		<td><a href="index.cgi?page=adv_basic_settings">Server Settings</a></td>
    	</tr>
    	<tr>
    		<td><a href="index.cgi?page=virt_hosts">Virtual Hosts</a></td>
    	</tr>
    	<tr>
    		<td><a href="index.cgi?page=zones">DNS Zones</a></td>
    	</tr>
    	<tr>
    		<td><a href="index.cgi?page=edit_apache">Edit Apache files</a></td>
    	</tr>
    	<tr>
    		<td><a href="index.cgi?page=edit_dns">Edit DNS zone file</a></td>
    	</tr>
    </table>
EOF
}

sub strip_quotes{
    my $string=shift;
    $string=~s/(['"])(.+?)\1/\2/g;
    return $string;
}

sub get_basic_settings{
    &get_apache_menu;
    my $admin_email = strip_quotes(&apache::find_directive("ServerAdmin", $main::httpd_conf));
    my $server_root = strip_quotes(&apache::find_directive("DocumentRoot", $main::httpd_conf));
    print <<EOF;
    <h2>Basic server settings</h2>
    <form action="index.cgi?page=apache_simple&amp;action=save_basic" method="POST" name="Basic_settings">
    <table cellpadding="4" cellspacing="1" summary="">
    	<tr>
    		<td>Administrator email:</td>
    		<td><input type="text" name="admin_email" value="$admin_email"></td>
    	</tr>
    	<tr>
    		<td>Server root directory:</td>
    		<td><input type="text" name="server_root" value="$server_root"></td>
    	</tr>
    	<tr>
    		<td>&nbsp;</td>
    		<td><input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel"></td>
    	</tr>
    </table>
    </form>
EOF
}

sub get_subdomains{
    &get_apache_menu;
    my $i=0;
    
    print <<EOF;
    <h2>Sub Domains</h2>
    <table cellspacing="1" cellpadding="3" summary="">
	<tr>
	    <th>Name</th>
	    <th>Document Root</th>
	    <th>Action</th>
	</tr>
EOF
    
    my @nvhosts=&apache::find_directive("NameVirtualHost",$main::httpd_conf);
    my @vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
    my $subs_cnt=0;
    for my $vhost (@vhosts){
	my $server_name=strip_quotes(&apache::find_directive("ServerName", $vhost->{'members'}));
	my $doc_root=strip_quotes(&apache::find_directive("DocumentRoot", $vhost->{'members'}));
	if($server_name){
	    my @level=split(/\./,$server_name);
	    if($#level>1){
		$subs_cnt++;
		print <<EOF;
		<tr>
		    <td>$server_name</td>
		    <td>$doc_root</td>
		    <td><a href="index.cgi?page=subdomains&amp;action=del_subdomain&amp;id=$i" class="red">Delete</a></td>
		</tr>
EOF
	    }
	}
	$i++;
    }
    if($subs_cnt==0){
	print <<EOF;
		<tr>
		    <td colspan=3>There are no subdomains</td>
		</tr>
EOF
    }
    print "</table>";
    my $doc_root=strip_quotes(&apache::find_directive("DocumentRoot",$main::httpd_conf));
    $doc_root=~s/\/$//;
    print <<EOF;
    <br>
    <h2>Add new sub domain</h2>
    <form action="index.cgi?page=subdomains&amp;action=add_subdomain" method="POST" name="subdomains">
    <table cellpadding="3" cellspacing="1" summary="">
    	<tr>
    		<td>Subdomain name:</td>
    		<td><input type="text" name="name" onkeyup="document.getElementById('root').value='$doc_root/'+this.value"> . 
	<select name="domain">
	    <option value="">--------</option>
EOF
    for $vhost (@vhosts){
	my $sname=&apache::find_directive("ServerName",$vhost->{members});
	if($sname){
	    @level=split(/\./,$sname);
	    if($#level>=1){
		print "<option value=\"$sname\">$sname</option>";
	    }
	}
    }
    print <<EOF;
	</select></td>
	</tr>
	<tr>
		<td>Subdomain root directory:</td>
		<td><input id="root" type="text" name="root" value="$doc_root/"></td>
	</tr>
	<tr>
		<td>&nbsp;</td>
		<td><input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel"></td>
	</tr>
	</table>
    </form>
EOF
}

sub get_domains{
    &get_apache_menu;
    my $i=0;
    
    print <<EOF;
    <h2>Domains</h2>
    <table cellpadding="5" cellspacing="1" summary="">
	<tr>
	    <th>Name</th>
	    <th>Document Root</th>
	    <th>Action</th>
	</tr>
EOF
    
    my @nvhosts=&apache::find_directive("NameVirtualHost",$main::httpd_conf);
    my @vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
    my $subs_cnt=0;
    for my $vhost (@vhosts){
	my $server_name=strip_quotes(&apache::find_directive("ServerName", $vhost->{'members'}));
	my $doc_root=strip_quotes(&apache::find_directive("DocumentRoot", $vhost->{'members'}));
	if($server_name){
	    my @level=split(/\./,$server_name);
	    if($#level<=1){
		$subs_cnt++;
		print <<EOF;
		<tr>
		    <td>$server_name</td>
		    <td>$doc_root</td>
		    <td><a href="index.cgi?page=domains&amp;action=del_domain&amp;id=$i" class="red">Delete</a></td>
		</tr>
EOF
	    }
	}
	$i++;
    }
    if($subs_cnt==0){
	print <<EOF;
		<tr>
		    <td colspan=3>There are no domains</td>
		</tr>
EOF
    }
    print "</table>";
    my $doc_root=strip_quotes(&apache::find_directive("DocumentRoot",$main::httpd_conf));
    $doc_root=~s/\/$//;
    print <<EOF;
    <br>
    <h2>Add new domain</h2>
    <form action="index.cgi?page=domains&amp;action=add_domain" method="POST" name="domains">
    <table cellpadding="3" cellspacing="1" summary="">
    	<tr>
    		<td>Domain name:</td>
    		<td><input type="text" name="name" onkeyup="document.getElementById('root').value='$doc_root/'+this.value"></td>
    	</tr>
    	<tr>
    		<td>Domain root directory:</td>
    		<td><input id="root" type="text" name="root" value="$doc_root/"></td>
    	</tr>
    	<tr>
    		<td>&nbsp;</td>
    		<td><input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel"></td>
    	</tr>
    </table>
    </form>
EOF
}

sub get_domains_for_access{
    &get_apache_menu;
    my $i=0;
    
    print <<EOF;
    <h2>Restrict access to specific site</h2>
    <table cellspacing="1" cellpadding="5" summary="">
	<tr>
	    <th>Name</th>
	    <th>Document Root</th>
	    <th>Manage Access</th>
	</tr>
EOF
    
    my @vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
    my $subs_cnt=0;
    for my $vhost (@vhosts){
	$server_name=strip_quotes(&apache::find_directive("ServerName", $vhost->{'members'}));
	$doc_root=strip_quotes(&apache::find_directive("DocumentRoot", $vhost->{'members'}));
	if($server_name){
	    my @level=split(/\./,$server_name);
	    if($#level<=1){
		$subs_cnt++;
		print <<EOF;
		<tr>
		    <td>$server_name</td>
		    <td>$doc_root</td>
		    <td><a href="index.cgi?page=man_access&amp;id=$i">Manage</a></td>
		</tr>
EOF
	    }
	}
	$i++;
    }
    if($subs_cnt==0){
	print <<EOF;
		<tr>
		    <td colspan=3>There are no domains to manage</td>
		</tr>
EOF
    }
    print "</table>";
}

sub get_man_access{
    my $id=shift;
    &get_apache_menu;
    if(!$id){
	&main::error("No ID parameter");
    }
    my @vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
    my $vhost=$vhosts[$id];
    my $domain=&apache::find_directive("ServerName", $vhost->{'members'});
    my $directory=&apache::find_directive_struct("Directory", $vhost->{'members'});
    my $order=&apache::find_directive("Order", $directory->{'members'});
    my $allow=&apache::find_directive("Allow", $directory->{'members'});
    my $deny=&apache::find_directive("Deny", $directory->{'members'});
    my $str='', $ad='', $da='';
    $allow=~s/from\s+?//;
    $deny=~s/from\s+?//;
    
    $allow='' if $allow eq 'all';
    $deny='' if $deny eq 'all';
    
    @allows=split(" ", $allow);
    @denys=split(" ", $deny);
    
    $allow_str=join(", ",@allows);
    $deny_str=join(", ",@denys);
    
    $allow_txt=join("\n",@allows);
    $deny_txt=join("\n",@denys);
    
    if($order=~/Deny\s*,\s*Allow/){
	if($allow ne ''){
	    $str='Allowed only for ' . $allow_str;
	}
	else{
	    $str='Denied for all';
	}
	$da=" checked";
    }
    else{
	if($deny ne ''){
	    $str='Denied for ' . $deny_str;
	}
	else{
	    $str='Allowed for all';
	}
	$ad=" checked";
    }
    
    print <<EOF;
    <h2>Modifying access control for <b>$domain</b></h2>
    <h3>Current status: $str</h3>
    <form action="index.cgi?page=access&amp;action=save_access&amp;id=$id" method="POST" name="domains">
    	<table cellpadding="3" cellspacing="1" summary="">
    		<tr>
    			<td><input type="radio" name="order" value="da"$da></td>
    			<td>Allow only these hosts to connect (one host by line)</td>
    		</tr>
    		<tr>
    			<td>&nbsp;</td>
    			<td><textarea name="allow_list" rows=6 cols=30>$allow_txt</textarea></td>
    		</tr>
    		<tr>
    			<td><input type="radio" name="order" value="ad"$ad></td>
    			<td>Deny these hosts to connect (one host by line)</td>
    		</tr>
    		<tr>
    			<td>&nbsp;</td>
    			<td><textarea name="deny_list" rows=6 cols=30>$deny_txt</textarea></td>
    		</tr>
    		<tr>
    			<td>&nbsp;</td>
    			<td><input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel"></td>
    		</tr>
    	</table>
    </form>
EOF
}


sub get_adv_basic_settings{
    &get_apache_menu;
    my $admin_email = strip_quotes(&apache::find_directive("ServerAdmin", $main::httpd_conf));
    my $server_root = strip_quotes(&apache::find_directive("DocumentRoot", $main::httpd_conf));
    my $server_name = strip_quotes(&apache::find_directive("ServerName", $main::httpd_conf));
    my $listen_txt = join("\n", &apache::find_directive("Listen", $main::httpd_conf));
    my $nvhosts_txt = join("\n", &apache::find_directive("NameVirtualHost", $main::httpd_conf));
    
    my $req_tmout = strip_quotes(&apache::find_directive("Timeout", $main::httpd_conf));
    my $kpalive_tmout = strip_quotes(&apache::find_directive("KeepAliveTimeout", $main::httpd_conf));
    my $LimitRequestFields = strip_quotes(&apache::find_directive("LimitRequestFields", $main::httpd_conf));
    my $LimitRequestLine = strip_quotes(&apache::find_directive("LimitRequestLine", $main::httpd_conf));
    my $MaxRequestsPerChild = strip_quotes(&apache::find_directive("MaxRequestsPerChild", $main::httpd_conf));
    my $LimitRequestFieldsize = strip_quotes(&apache::find_directive("LimitRequestFieldsize", $main::httpd_conf));
    my $SendBufferSize = strip_quotes(&apache::find_directive("SendBufferSize", $main::httpd_conf));
    my $ListenBacklog = strip_quotes(&apache::find_directive("ListenBacklog", $main::httpd_conf));
    
    my $user = strip_quotes(&apache::find_directive("User", $main::httpd_conf));
    my $group = strip_quotes(&apache::find_directive("Group", $main::httpd_conf));
    
    print <<EOF;
    <h2>Basic server settings</h2>
    <form action="index.cgi?page=apache_adv&amp;action=save_adv_basic_settings" method="POST" name="Adv_basic_settings">
    <table cellpadding="3" cellspacing="1" summary="">
    	<tr>
    		<td>Administrator email:</td>
    		<td><input type="text" name="admin_email" value="$admin_email"></td>
    	</tr>
    	<tr>
    		<td>Server root directory:</td>
    		<td><input type="text" name="server_root" value="$server_root"></td>
    	</tr>
    	<tr>
    		<td>Main server name:</td>
    		<td><input type="text" name="server_name" value="$server_name"></td>
    	</tr>
    	<tr>
    		<td>Server listen addresses:ports (one by line)</td>
    		<td><textarea name="listen" rows=6 cols=30>$listen_txt</textarea></td>
    	</tr>
    	<tr>
    		<td>NameVirtualHosts (one by line)</td>
    		<td><textarea name="nvhosts" rows=6 cols=30>$nvhosts_txt</textarea></td>
    	</tr>
    	<tr>
    		<th colspan="2">
    			<h3>Resourse Limits</h3><br>
    			<h5>Note: Leave empty any field for default value</h5>
    		</th>
    	</tr>
    	<tr>
			<td>Request timeout:</td>
			<td><input type="text" name="req_tmout" value="$req_tmout"></td>
		</tr>
		<tr>
			<td>KeepAlive timeout:</td>
			<td><input type="text" name="kpalive_tmout" value="$kpalive_tmout"></td>
		</tr>
		<tr>
			<td>Limit Request Fields:</td>
			<td><input type="text" name="LimitRequestFields" value="$LimitRequestFields"></td>
		</tr>
		<tr>
			<td>Limit Request Line:</td>
			<td><input type="text" name="LimitRequestLine" value="$LimitRequestLine"></td>
		</tr>
		<tr>
			<td>Max Requests Per Child:</td>
			<td><input type="text" name="MaxRequestsPerChild" value="$MaxRequestsPerChild"></td>
		</tr>
		<tr>
			<td>Limit Request Field size:</td>
			<td><input type="text" name="LimitRequestFieldsize" value="$LimitRequestFieldsize"></td>
		</tr>
		<tr>
			<td>Send Buffer Size:</td>
			<td><input type="text" name="SendBufferSize" value="$SendBufferSize"></td>
		</tr>
		<tr>
			<td>Listen Back log:</td>
			<td><input type="text" name="ListenBacklog" value="$ListenBacklog"></td>
		</tr>
		<tr>
			<th colspan="2"><h3>User/Group</h3></th>
		</tr>
		<tr>
			<td>User:</td>
			<td><input type="text" name="user" value="$user"></td>
		</tr>
		<tr>
			<td>Group:</td>
			<td><input type="text" name="group" value="$group"></td>
		</tr>
		<tr>
			<td>&nbsp;</td>
			<td><input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel"></td>
		</tr>
	</table>
    </form>
EOF
}

sub get_virt_hosts{
    &get_apache_menu;
    my $i=0;
    
    print <<EOF;
    <h2>Manage virtual hosts</h2>
    <table cellspacing="1" cellpadding="5" summary="">
	<tr>
	    <th>Name</th>
	    <th>Document Root</th>
	    <th>Manage</th>
	</tr>
EOF
    my $server_root = strip_quotes(&apache::find_directive("DocumentRoot", $main::httpd_conf));
    my @vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
    my $vh_cnt=0;
    for my $vhost (@vhosts){
	$server_name=strip_quotes(&apache::find_directive("ServerName", $vhost->{'members'}));
	$doc_root=strip_quotes(&apache::find_directive("DocumentRoot", $vhost->{'members'}));
	if($server_name){
	    $vh_cnt++;
	    print <<EOF;
	    <tr>
		<td>$server_name</td>
		<td>$doc_root</td>
		<td>
		    <a href="index.cgi?page=edit_vhost&amp;vid=$i">Edit</a>&nbsp;&nbsp;&nbsp; | &nbsp;
		    <a href="index.cgi?page=virt_hosts&amp;action=del_vhost&amp;id=$i" class="red">Delete</a>
		</td>
	    </tr>
EOF
	}
	$i++;
    }
    if($vh_cnt==0){
	print <<EOF;
		<tr>
		    <td colspan=3>There are no virtual hosts to manage</td>
		</tr>
EOF
    }
    print <<EOF
    </table>
    <h2>Add new virtual host</h2>
    <form action="index.cgi?page=virt_hosts&amp;action=add_vhost" method="POST" name="new_vhost">
    <table cellpadding="5" cellspacing="1" summary="">
    	<tr>
    		<td>Domain name:</td>
    		<td><input type="text" name="name" onkeyup="document.getElementById('root').value='$server_root/'+this.value"></td>
    	</tr>
    	<tr>
    		<td>Document root directory:</td>
    		<td><input id="root" type="text" name="root" value="$server_root/"></td>
    	</tr>
    	<tr>
    		<td>Listen address:</td>
    		<td><input type="text" name="listen_addr" value="*"></td>
    	</tr>
    	<tr>
    		<td>Listen port:</td>
    		<td><input type="text" name="listen_port" value="80"></td>
    	</tr>
    	<tr>
    		<td>Server Aliases(one by line):</td>
    		<td><textarea name="aliases" rows=6 cols=30></textarea></td>
    	</tr>
    	<tr>
    		<td>&nbsp;</td>
    		<td><input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel"></td>
    	</tr>
    	</table>
    </form>
EOF
}

sub get_edit_vhost{
    my $id = shift;
    &get_apache_menu;
    my @vhosts=&apache::find_directive_struct("VirtualHost",$main::httpd_conf);
    
    my $vhost=$vhosts[$id]->{'members'};
    
    my $ServerName = strip_quotes(&apache::find_directive("ServerName", $vhost));
    my $DocumentRoot = strip_quotes(&apache::find_directive("DocumentRoot", $vhost));
    my $ServerAdmin = strip_quotes(&apache::find_directive("ServerAdmin", $vhost));
    my $ServerAlias = join("\n", &apache::find_directive("ServerAlias", $vhost));

    my $LimitRequestBody = strip_quotes(&apache::find_directive("LimitRequestBody", $vhost));
    my $LimitXMLRequestBody = strip_quotes(&apache::find_directive("LimitXMLRequestBody", $vhost));
    my ($RLimitCPU_0,$RLimitCPU_1) = @{&apache::find_directive_struct("RLimitCPU", $vhost)->{'words'}} if &apache::find_directive_struct("RLimitCPU", $vhost);
    my ($RLimitMEM_0,$RLimitMEM_1) = @{&apache::find_directive_struct("RLimitMEM", $vhost)->{'words'}} if &apache::find_directive_struct("RLimitMEM", $vhost);
    my ($RLimitNPROC_0,$RLimitNPROC_1) = @{&apache::find_directive_struct("RLimitNPROC", $vhost)->{'words'}} if &apache::find_directive_struct("RLimitNPROC", $vhost);
    my $ErrorLog = strip_quotes(&apache::find_directive("ErrorLog", $vhost));
    my ($CustomLog,$log_type) = @{&apache::find_directive_struct("CustomLog", $vhost)->{'words'}} if &apache::find_directive_struct("CustomLog", $vhost);
    my $LogLevel = strip_quotes(&apache::find_directive("LogLevel", $vhost));
    
    my ($user,$group) = @{&apache::find_directive_struct("SuexecUserGroup", $vhost)->{'words'}} if &apache::find_directive_struct("SuexecUserGroup", $vhost);
    
    @warn_levels= (
		   {'emerg'=>'Emergency'},
		   {'alert'=>'Alert'},
		   {'crit'=>'Critical'},
		   {'error'=>'Error'},
		   {'warn'=>'Warning'},
		   {'notice'=>'Notice'},
		   {'info'=>'Information'},
		   {'debug'=>'Debug'}
		   );
    
    print <<EOF;
    <h2>Editing $ServerName</h2>
    <h5>Note: Leave empty any non mandatory field for default value</h5>
    <form action="index.cgi?page=virt_hosts&amp;action=save_vhost&amp;id=$id" method="POST" name="EditVhost">
    <table cellpadding="5" cellspacing="1" summary="">
    	<tr>
    		<td>Server name *:</td>
    		<td colspan="3"><input type="text" name="ServerName" value="$ServerName"></td>
    	</tr>
    	<tr>
    		<td>Server root directory *:</td>
    		<td colspan="3"><input type="text" name="DocumentRoot" value="$DocumentRoot"></td>
    	</tr>
    	<tr>
    		<td>Administrator email:</td>
    		<td colspan="3"><input type="text" name="ServerAdmin" value="$ServerAdmin"></td>
    	</tr>
    	<tr>
    		<td>Server aliases(one by line)</td>
    		<td colspan="3"><textarea name="ServerAlias" rows=6 cols=30>$ServerAlias</textarea></td>
    	</tr>
    	<tr>
    		<th colspan="4"><h3>Resourse Limits</h3></th>
    	</tr>
    	<tr>
    		<td>Request body limit:</td>
    		<td colspan="3"><input type="text" name="LimitRequestBody" value="$LimitRequestBody"></td>
    	</tr>
    	<tr>
    		<td>XML Request body limit:</td>
    		<td colspan="3"><input type="text" name="LimitXMLRequestBody" value="$LimitXMLRequestBody"></td>
    	</tr>
    	<tr>
    		<td><strong>CPU limit:</strong> soft:</td>
    		<td><input type="text" size="6" name="RLimitCPU_0" value="$RLimitCPU_0"></td>
    		<td>hard:</td>
    		<td><input type="text" size="6" name="RLimitCPU_1" value="$RLimitCPU_1"></td>
    	</tr>
    	<tr>
    		<td><strong>Memoty limit:</strong> soft:</td>
    		<td><input type="text" size="6" name="RLimitMEM_0" value="$RLimitMEM_0"></td>
    		<td>hard:</td>
    		<td><input type="text" size="6" name="RLimitMEM_1" value="$RLimitMEM_1"></td>
    	</tr>
    	<tr>
    		<td><strong>Process limit:</strong> soft:</td>
    		<td><input type="text" size="6" name="RLimitNPROC_0" value="$RLimitNPROC_0"></td>
    		<td>hard:</td>
    		<td><input type="text" size="6" name="RLimitNPROC_1" value="$RLimitNPROC_1"></td>
    	</tr>
    	<tr>
    		<th colspan="4"><h3>Logging</h3></th>
    	</tr>
    	<tr>
    		<td>Error log:</td>
    		<td colspan="3">
    			<input type="text" name="ErrorLog" value="$ErrorLog">&nbsp;&nbsp;
				<select name="warn_level">
EOF
				for $i (@warn_levels){
				    ($key, $val)=each(%$i);
                                    if($key eq $LogLevel){
                                        print '<option value="' . $key .'" selected>'.$val.'</option>';
                                    }
                                    else{
                                        print '<option value="' . $key .'">'.$val.'</option>';
                                    }
				}
				print <<EOF;
				</select>
			</td>
		</tr>
		<tr>
			<td>Combined Access Log:</td>
			<td colspan="3"><input type="text" name="CustomLog" value="$CustomLog"></td>
		</tr>
		<tr>
			<th colspan="4"><h3>User/Group</h3></th>
		</tr>
		<tr>
			<td>User:</td>
			<td colspan="3"><input type="text" name="user" value="$user"></td>
		</tr>
		<tr>
			<td>Group:</td>
			<td colspan="3"><input type="text" name="group" value="$group"></td>
		</tr>
		<tr>
			<td>&nbsp;</td>
			<td colspan="3"><input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel"></td>
		</tr>
	</table>
    </form>
EOF
}

sub get_zones{
    &get_apache_menu;
    
    print <<EOF;
    <h2>Manage DNS zones</h2>
    <table cellspacing="1" cellpadding="5">
	<tr>
	    <th>Name</th>
	    <th>Manage</th>
	</tr>
EOF
    my @zones=&bind::find("zone",$main::bind_conf);
    if($#zones!=-1){
	for my $zone (@zones){
	    if($zone->{'value'} and $zone->{'value'} ne '.'){
		$zname=&bind::arpa_to_ip($zone->{'value'});
		print <<EOF;
		<tr>
		    <td>$zname</td>
		    <td>
			<a href="index.cgi?page=edit_zone&amp;id=$i">Edit</a>&nbsp;&nbsp;&nbsp; |&nbsp;&nbsp; 
			<a href="index.cgi?page=zones&amp;action=del_zone&amp;id=$i" class="red">Delete</a>
		    </td>
		</tr>
EOF
	    }
	    $i++;
	}
    }
    else{
	print <<EOF;
		<tr>
		    <td colspan=2>There are no zones to manage</td>
		</tr>
EOF
    }
    print <<EOF
    </table>
    <h2>Add new zone</h2>
    <form action="index.cgi?page=zones&amp;action=add_zone" method="POST" name="new_zone">
    <table cellpadding="5" cellspacing="1" summary="">
    	<tr>
    		<td>Domain name *:</td>
    		<td><input type="text" name="name" ></td>
    	</tr>
    	<tr>
    		<td>Master server *:</td>
    		<td><input type="text" name="master" value="$main::CONFIG{'SERVER_HOSTNAME'}"></td>
    	</tr>
    	<tr>
    		<td>Email address *:</td>
    		<td><input type="text" name="email" value="$main::CONFIG{'SERVER_EMAIL'}"></td>
    	</tr>
    	<tr>
    		<td>IP address to point:</td>
    		<td><input type="text" name="ip" value="$main::CONFIG{'SERVER_MAIN_IP'}"></td>
    	</tr>
    	<tr>
    		<td>Domain aliases(one by line)</td>
    		<td><textarea name="aliases" rows=6 cols=30></textarea></td>
    	</tr>
    	<tr>
    		<td>Refresh time *:</td>
    		<td>
    			<input size="6" type="text" name="refresh" value="10800">&nbsp;&nbsp;
    			<select name="refunit" size=1 >
					<option value="" selected>seconds</option>
					<option value="M">minutes</option>
					<option value="H">hours</option>
					<option value="D">days</option>
					<option value="W">weeks</option>
		    	</select>
		    </td>
    	</tr>
    	<tr>
    		<td>Expiry time *:</td>
    		<td>
    			<input size="6" type="text" name="expiry" value="604800">&nbsp;&nbsp;
	    		<select name="expunit" size=1 >
					<option value="" selected>seconds</option>
					<option value="M">minutes</option>
					<option value="H">hours</option>
					<option value="D">days</option>
					<option value="W">weeks</option>
	    		</select>
	    	</td>
	    </tr>
	    <tr>
	    	<td>Transfer retry time *:</td>
	    	<td>
	    		<input size="6" type="text" name="transfer" value="3600">&nbsp;&nbsp;
				<select name="tranunit" size=1 >
					<option value="" selected>seconds</option>
					<option value="M">minutes</option>
					<option value="H">hours</option>
					<option value="D">days</option>
					<option value="W">weeks</option>
				</select>
			</td>
		</tr>
		<tr>
			<td>Negative cache time *:</td>
			<td>
				<input size="6" type="text" name="cache" value="38400">&nbsp;&nbsp;
				<select name="chahceunit" size=1 >
					<option value="" selected>seconds</option>
					<option value="M">minutes</option>
					<option value="H">hours</option>
					<option value="D">days</option>
					<option value="W">weeks</option>
	    		</select>
	    	</td>
	    </tr>
	    <tr>
	    	<td>&nbsp;</td>
	    	<td><input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel"></td>
	    </tr>
	   </table>
    </form>
EOF
}

sub get_edit_zone{
    my $id=shift;
    &get_apache_menu;
    my @zones=&bind::find("zone",$main::bind_conf);
    my $zone=$zones[$id];
    $zone_file=&bind::find("file", $zones[$id]->{'members'})->{'value'};
    $named_root=&bind::find("directory", &bind::find("options", $main::bind_conf)->{'members'})->{'value'};
    $named_root=~s/\/$//;
    $named_root=~s/^\///;
    $zone_file=$main::CONFIG{'BIND_CHROOT'} . $named_root . '/' . $zone_file;
    open(FL, $zone_file) or &main::error("Can't open file for reading: $!");
    while(<FL>){
	$zone_txt.=$_;
    }
    close FL;
    print <<EOF;
    <h2>Edit zone $zone->{'value'}</h2>
    <form action="index.cgi?page=zones&amp;action=save_zone&amp;id=$id" method="POST" name="save_zone">
	<textarea name="zone_file" rows=18 cols=80>$zone_txt</textarea><br>
	<br>
	<input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel">
    </form>
EOF
}

sub get_edit_apache{
    &get_apache_menu;
    my $my_file=$main::CONFIG{'APACHE_CONF_PATH'};
    print <<EOF;
    <h2>Edit Apache config files</h2>
    <form action="index.cgi" method="GET" name="ch_file">
	<input type="hidden" name="page" value="edit_apache">
	<select name="file">
EOF
    my @files = grep { -f $_ } &main::unique(map { $_->{'file'} } @$main::httpd_conf);
    foreach (@files){
	if(&main::url_param('file') eq $_){
	    $my_file=$_;
	    print "<option value=\"$_\" selected>$_</option>";
	}
	else{
	    print "<option value=\"$_\">$_</option>";
	}
    }
    
    open(FL, $my_file) or &main::error("Can't open file for reading: $!");
    while(<FL>){
	$txt.=$_;
    }
    close FL;
    
    print <<EOF;
	</select>
	<input type="submit" value="Change">
    </form>
    <form action="index.cgi?page=apache_adv&amp;action=save_apache" method="POST" name="save_apache">
	<input type="hidden" name="file" value="$my_file">
	<textarea name="text" rows=25 cols=100>$txt</textarea><br>
	<br>
	<input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel">
    </form>
EOF
}

sub get_edit_dns{
    &get_apache_menu;
    my $my_file=$main::CONFIG{'BIND_NAMED_CONF'};
    
    open(FL, $my_file) or &main::error("Can't open file for reading: $!");
    while(<FL>){
	$txt.=$_;
    }
    close FL;
    
    print <<EOF;
    <h2>Edit DNS zone file</h2>
    <form action="index.cgi?page=apache_adv&amp;action=save_dns" method="POST" name="save_dns">
	<textarea name="text" rows=25 cols=100>$txt</textarea><br>
	<br>
	<input type="submit" value="Save">&nbsp;&nbsp;&nbsp;<input type="button" onclick="history.go(-1)" value="Cancel">
    </form>
EOF
}
1;
