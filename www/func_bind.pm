#!/usr/bin/perl

package bind;

# get_config()
sub get_config{
    @config = &read_config_file($main::CONFIG{'BIND_NAMED_CONF'});
    return \@config;
}

# read_config_file(file, [expand includes])
sub read_config_file{
    my ($config_file, $do_not_expand_includes)=@_;
    my ($lnum, $line, $cmode, @ltok, @lnum, @tok, @rv, $i, $t, $j, $ifile, @inc, $str);
    $lnum = 0;
    open(FILE, $config_file);
    while($line = <FILE>) {
        $line =~ s/\r|\n//g;
        $line =~ s/#.*$//g;
        $line =~ s/\/\/.*$//g if ($line !~ /".*\/\/.*"/);
        $line =~ s/\/\*.*\*\///g;
        while(1) {
            if (!$cmode && $line =~ /\/\*/) {
                # start of a C-style comment
                $cmode = 1;
                $line =~ s/\/\*.*$//g;
            }
            elsif ($cmode) {
                if ($line =~ /\*\//) {
                    # end of comment
                    $cmode = 0;
                    $line =~ s/^.*\*\///g;
                }
                else {
                    $line = "";
                    last;
                }
            }
            else {
                last;
            }
        }

        undef(@ltok);
        while(1) {
            if ($line =~ /^\s*\"([^"]*)"(.*)$/) {
                push(@ltok, $1);
                $line = $2;
            }
            elsif ($line =~ /^\s*([{};])(.*)$/) {
                push(@ltok, $1);
                $line = $2;
            }
            elsif ($line =~ /^\s*([^{}; \t]+)(.*)$/) {
                push(@ltok, $1);
                $line = $2;
            }
            else {
                last;
            }
        }
        foreach $t (@ltok) {
            push(@tok, $t);
            push(@lnum, $lnum);
        }
        $lnum++;
    }
    close(FILE);
    $lines_count{$config_file} = $lnum;
    
    $i = 0;
    $j = 0;
    while($i < @tok) {
        $str = &parse_struct(\@tok, \@lnum, \$i, $j++, $config_file);
        if ($str) {
            push(@rv, $str);
        }
    }
    if (!@rv) {
        push(@rv, { 'name' => 'dummy',
                    'line' => 0,
                    'eline' => 0,
                    'index' => 0,
                    'file' => $_[0] });
    }
    
    if (!$do_not_expand_includes) {
        while(&recursive_includes(\@rv, &get_base_directory(\@rv))) {}
    }
    
    return @rv;
}

# parse_struct(&tokens, &lines, &line_num, index, file)
# A structure can either have one value, or a list of values.
# Pos will end up at the start of the next structure
sub parse_struct{
    my ($tokens, $lines, $line_num, $index, $config_file)=@_;
    local (%str, $i, $j, $t, @vals, $str);
    $i = ${$line_num};
    $str{'name'} = lc($tokens->[$i]);
    $str{'line'} = $lines->[$i];
    $str{'index'} = $index;
    $str{'file'} = $config_file;
    if ($str{'name'} eq 'inet') {
        # The inet directive doesn't have sub-structures, just multiple
        # values with { } in them
        $str{'type'} = 2;
        $str{'members'} = { };
        while(1) {
            $t = $tokens->[++$i];
            if ($tokens->[$i+1] eq "{") {
                # Start of a named sub-structure ..
                $i += 2;	# skip {
                $j = 0;
                while($tokens->[$i] ne "}") {
                    $str = &parse_struct($tokens, $lines, \$i, $j++, $config_file);
                    if ($str) {
                        push(@{$str{'members'}->{$t}}, $str);
                    }
                }
                next;
            }
            elsif ($t eq ";") {
                last;
            }
            push(@vals, $t);
        }
        $i++;	# skip trailing ;
        $str{'values'} = \@vals;
        $str{'value'} = $vals[0];
    }
    else {
        # Normal directive, like foo bar; or foo bar { smeg; };
        while(1) {
            $t = $tokens->[++$i];
            if ($t eq "{" || $t eq ";" || $t eq "}") {
                last;
            }
            elsif (!defined($t)) {
                ${$line_num} = $i;
                return undef;
            }
            else {
                push(@vals, $t);
            }
        }
        $str{'values'} = \@vals;
        $str{'value'} = $vals[0];
        if ($t eq "{") {
            # contains sub-structures.. parse them
            local(@mems, $j);
            $i++;		# skip {
            $str{'type'} = 1;
            $j = 0;
            while($tokens->[$i] ne "}") {
                if (!defined($tokens->[$i])) {
                    ${$line_num} = $i;
                    return undef;
                }
                $str = &parse_struct($tokens, $lines, \$i, $j++, $config_file);
                if ($str) {
                    push(@mems, $str);
                }
            }
            $str{'members'} = \@mems;
            $i += 2;	# skip trailing } and ;
        }
        else {
            # only a single value..
            $str{'type'} = 0;
            if ($t eq ";") {
                $i++;	# skip trailing ;
            }
        }
    }
    $str{'eline'} = $lines->[$i-1]; # ending line is the line number the trailing ;
    ${$line_num} = $i;
    return \%str;
}

# recursive_includes(&dirs, base)
sub recursive_includes{
    my ($dirs, $base) = @_;
    my ($i, $j);
    my $any = 0;
    for($i=0; $i<@{$dirs}; $i++) {
        if (lc($dirs->[$i]->{'name'}) eq "include") {
            # found one.. replace the include directive with it
            $ifile = $dirs->[$i]->{'value'};
            if ($ifile !~ /^\//) {
                $ifile = "$base/$ifile";
            }
            my @inc = &read_config_file($ifile, 1);

            # update index of included structures
            my $j;
            for($j=0; $j<@inc; $j++) {
                $inc[$j]->{'index'} += $dirs->[$i]->{'index'};
            }

            # update index of structures after include
            for($j=$i+1; $j<@{$dirs}; $j++) {
                $dirs->[$j]->{'index'} += scalar(@inc) - 1;
            }
            splice(@{$dirs}, $i--, 1, @inc);
            $any++;
        }
        elsif ($dirs->[$i]->{'type'} == 1) {
            # Check sub-structures too
            $any += &recursive_includes($dirs->[$i]->{'members'}, $base);
        }
    }
    return $any;
}

sub get_base_directory{
    local ($opts, $dir, $conf);
    $conf = $_[0] ? $_[0] : &get_config();
    if (($opts = &find("options", $conf)) && ($dir = &find("directory", $opts->{'members'}))) {
        return $dir->{'value'};
    }
    if ($main::CONFIG{'BIND_NAMED_CONF'} =~ /^(.*)\/[^\/]+$/ && $1) {
        return $1;
    }
    return "/etc";
}

# find(name, &array)
sub find{
    my ($name, $array) = @_;
    my($c, @rv);
    foreach $c (@{$array}) {
        if ($c->{'name'} eq $name) {
            push(@rv, $c);
        }
    }
    return @rv ? wantarray ? @rv : $rv[0] : wantarray ? () : undef;
}

# read_zone_file(file, origin, [previous], [only-soa])
# Reads a DNS zone file and returns a data structure of records. The origin
# must be a domain without the trailing dot, or just .
sub read_zone_file{
    my ($file, $origin, $previous, $only_soa) = @_;
    local($lnum, $line, $t, @tok, @lnum, @coms,
          $i, @rv, $num, $j, @inc, @oset, $comment);
    $file_without_slash=$file;
    $file_without_slash=~s/^\///;
    local $rootfile = $main::CONFIG{'BIND_CHROOT'} . $file_without_slash;
    open(FILE, $rootfile);
    $lnum = 0;
    local ($gotsoa, $aftersoa);
    while($line = <FILE>) {
        local($glen, $merged_2, $merge);
        $line =~ s/\r|\n//g;
        if ($line =~ /;/ &&
            ($line =~ /[^\\]/ &&
             $line =~ /^((?:[^;\"]+|\"\"|(?:\"(?:[^\"]*)\"))*);(.*)/) ||
            ($line =~ /[^\"]/ &&
             $line =~ /^((?:[^;\\]|\\.)*);(.*)/) ||
             $line =~ /^((?:(?:[^;\"\\]|\\.)+|(?:\"(?:[^\"\\]|\\.)*\"))*);(.*)/) {
                $comment = $2;
                $line = $1;
                if ($line =~ /^[^"]*"[^"]*$/) {
                   $line .= $comment;
                    $comment = "";
                }
        }
        else { 
            $comment = "";
        }

        local $oset = 0;
        while(1) {
            $merge = 1;
            $base_oset = 0;
            if ($line =~ /^(\s*)\"((?:[^\"\\]|\\.)*)\"(.*)/ ||
                $line =~ /^(\s*)((?:[^\s\(\)\"\\]|\\.)+)(.*)/ ||
                ($merge = 0) || $line =~ /^(\s*)([\(\)])(.*)/) {
                if ($glen == 0) {
                    $oset += length($1);
                }
                else {
                    $glen += length($1);
                }
                $glen += length($2);
                $merged_2 .= $2;
                $line = $3;
                if (!$merge || $line =~ /^([\s\(\)]|$)/) {
                    push(@tok, $merged_2);
                    push(@lnum, $lnum);
                    push(@oset, $oset);
                    push(@coms, $comment);
                    $comment = "";

                    if (uc($merged_2) eq "SOA") {
                        $gotsoa = 1;
                    }
                    elsif ($gotsoa) {
                        $aftersoa++;
                    }

                    $merged_2 = "";
                    $oset += $glen;
                    $glen = 0;
                }
            }
            else { last; }
        }
        $lnum++;

        if ($aftersoa > 10 && $only_soa) {
            last;
        }
    }
    close(FILE);
    
    $i = 0;
    $num = 0;
    while($i < @tok) {
        if ($tok[$i] =~ /^\$origin$/i) {
            if ($tok[$i+1] =~ /^(\S*)\.$/) {
                $origin = $1 ? $1 : ".";
            }
            elsif ($origin eq ".") {
                $origin = $tok[$i+1];
            }
            else {
                $origin = "$tok[$i+1].$origin";
            }
            $i += 2;
        }
        elsif ($tok[$i] =~ /^\$include$/i) {
            if ($lnum[$i+1] == $lnum[$i+2]) {
                local $inc_origin;
                if ($tok[$i+2] =~ /^(\S+)\.$/) {
                    $inc_origin = $1 ? $1 : ".";
                }
                elsif ($origin eq ".") {
                    $inc_origin = $tok[$i+2];
                }
                else {
                    $inc_origin = "$tok[$i+2].$origin";
                }
                @inc = &read_zone_file($tok[$i+1], $inc_origin, @rv ? $rv[$#rv] : undef);
                $i += 3;
            }
            else {
                @inc = &read_zone_file($tok[$i+1], $origin, @rv ? $rv[$#rv] : undef);
                $i += 2;
            }
            foreach $j (@inc) {
                $j->{'num'} = $num++;
            }
            push(@rv, @inc);
        }
        elsif ($tok[$i] =~ /^\$generate$/i) {
            local $gen = { 'file' => $file,
                           'rootfile' => $rootfile,
                           'comment' => $coms[$i],
                           'line' => $lnum[$i],
                           'num' => $num++ };
            local @gv;
            while($lnum[++$i] == $gen->{'line'}) {
                push(@gv, $tok[$i]);
            }
            $gen->{'generate'} = \@gv;
            push(@rv, $gen);
        }
        elsif ($tok[$i] =~ /^\$ttl$/i) {
            $i++;
            local $defttl = { 'file' => $file,
                              'rootfile' => $rootfile,
                              'line' => $lnum[$i],
                              'num' => $num++,
                              'defttl' => $tok[$i++] };
            push(@rv, $defttl);
        }
        elsif ($tok[$i] =~ /^\$(\S+)/i) {
            local $ln = $lnum[$i];
            while($lnum[$i] == $ln) {
                $i++;
            }
        }
        else {
            local(%dir, @values, $l);
            $dir{'line'} = $lnum[$i];
            $dir{'file'} = $file;
            $dir{'rootfile'} = $rootfile;
            $dir{'comment'} = $coms[$i];
            if ($tok[$i] =~ /^(in|hs)$/i && $oset[$i] > 0) {
                $dir{'class'} = uc($tok[$i]);
                $i++;
            }
            elsif ($tok[$i] =~ /^\d/ && $tok[$i] !~ /in-addr/i && $oset[$i] > 0 && $tok[$i+1] =~ /^(in|hs)$/i) {
                $dir{'ttl'} = $tok[$i];
                $dir{'class'} = uc($tok[$i+1]);
                $i += 2;
            }
            elsif ($tok[$i+1] =~ /^(in|hs)$/i) {
                $dir{'name'} = $tok[$i];
                $dir{'class'} = uc($tok[$i+1]);
                $i += 2;
            }
            elsif ($oset[$i] > 0 && $tok[$i] =~ /^\d+/) {
                $dir{'ttl'} = $tok[$i];
                $dir{'class'} = "IN";
                $i++;
            }
            elsif ($oset[$i] > 0) {
                $dir{'class'} = "IN";
            }
            elsif ($tok[$i+1] =~ /^\d/ && $tok[$i+2] =~ /^(in|hs)$/i) {
                $dir{'name'} = $tok[$i];
                $dir{'ttl'} = $tok[$i+1];
                $dir{'class'} = uc($tok[$i+2]);
                $i += 3;
            }
            elsif ($tok[$i+1] =~ /^\d/) {
                $dir{'name'} = $tok[$i];
                $dir{'ttl'} = $tok[$i+1];
                $dir{'class'} = "IN";
                $i += 2;
            }
            else {
                $dir{'name'} = $tok[$i];
                $dir{'class'} = "IN";
                $i++;
            }
            if ($dir{'name'} eq '') {
                local $prv = $#rv >= 0 ? $rv[$#rv] : $previous;	
                $prv || die "Unexpected error!";
                $dir{'name'} = $prv->{'name'};
                $dir{'realname'} = $prv->{'realname'};
            }
            else {
                $dir{'realname'} = $dir{'name'};
            }
            $dir{'type'} = uc($tok[$i++]);

            $l = $lnum[$i];
            while($lnum[$i] == $l && $i < @tok) {
                if ($tok[$i] eq "(") {
                    my $olnum = $lnum[$i];
                    while($tok[++$i] ne ")") {
                        push(@values, $tok[$i]);
                        if ($i >= @tok) {
                            die("No ending ) found for ( starting at $olnum");
                        }
                    }
                    $i++;
                    last;
                }
                push(@values, $tok[$i++]);
            }
            $dir{'values'} = \@values;
            $dir{'eline'} = $lnum[$i-1];
            if (!$config{'short_names'}) {
                if ($dir{'name'} eq "@") {
                    $dir{'name'} = $origin eq "." ? "." : "$origin.";
                }
                elsif ($dir{'name'} !~ /\.$/) {
                    $dir{'name'} .= $origin eq "." ? "." : ".$origin.";
                }
            }
            $dir{'num'} = $num++;

            local $spf;
            if ($dir{'type'} eq 'TXT' && ($spf=&parse_spf($dir{'values'}->[0]))) {
                if (!@{$spf->{'other'}}) {
                    $dir{'type'} = 'SPF';
                }
            }

            push(@rv, \%dir);

            if ($dir{'type'} eq 'SOA' && $only_soa) {
                last;
            }
        }
    }
    return \@rv;
}

# create_record(file, name, ttl, class, type, values, comment)
sub create_record{
    local ($file, $name, $ttl, $class, $type, $values, $comment)=@_;
    $file_without_slash=$file;
    $file_without_slash=~s/^\///;
    local $rootfile = $main::CONFIG{'BIND_CHROOT'} . $file_without_slash;
    local $lref = &main::read_file($rootfile);
    push(@$lref, &make_record(@_[1..$#_]));
}

# make_record(name, ttl, class, type, values, comment)
sub make_record{
    local ($name, $ttl, $class, $type, $values, $comment)=@_;
    local $type = $type eq "SPF" ? "TXT" : $type;
    return $name . ($ttl ? "\t$ttl" : "") . "\t$class\t$type\t$values" . ($comment ? "\t;$comment" : "");
}

# delete_record(file, &old)
sub delete_record{
    my ($file, $old) = @_;
    local $file_without_slash=$file;
    $file_without_slash=~s/^\///;
    local $rootfile = $main::CONFIG{'BIND_CHROOT'} . $file_without_slash;
    local $lref = &main::read_file($rootfile);
    splice(@$lref, $old->{'line'}, $old->{'eline'} - $old->{'line'} + 1);
}

# create_zone(&zone, &conf)
sub create_zone{
    local ($dir, $conf) = @_;
    $dir->{'file'} = $main::CONFIG{'BIND_NAMED_CONF'};
    &save_directive(get_config_parent(), undef, [ $dir ], 0);
}

# save_directive(&parent, name|&old, &values, indent, [structonly])
sub save_directive{
    local ($parent, $old, $values, $indent, $structonly) = @_;
    local(@oldv, @newv, $pm, $i, $o, $n, $lref, @nl);
    $pm = $parent->{'members'};
    @oldv = ref($old) ? @{$old} : &find($old, $pm);
    @newv = @{$values};
    for($i=0; $i<@oldv || $i<@newv; $i++) {
        if ($i >= @oldv && !$_[5]) {
            # a new directive is being added.. put it at the end of
            # the parent
            if (!$structonly) {
                local $parent = &get_config_parent($newv[$i]->{'file'} || $parent->{'file'});
                $lref = &main::read_file($newv[$i]->{'file'} || $parent->{'file'});
                @nl = &directive_lines($newv[$i], $indent);
                splice(@$lref, $parent->{'eline'}, 0, @nl);
                $newv[$i]->{'file'} = $parent->{'file'};
                $newv[$i]->{'line'} = $parent->{'eline'};
                $newv[$i]->{'eline'} = $parent->{'eline'} + scalar(@nl) - 1;
                &renumber($parent, $parent->{'eline'}-1, $parent->{'file'}, scalar(@nl));
            }
            push(@$pm, $newv[$i]);
        }
        elsif ($i >= @oldv && $_[5]) {
            # a new directive is being added.. put it at the start of
            # the parent
            if (!$structonly) {
                local $parent = &get_config_parent($newv[$i]->{'file'} || $parent->{'file'});
                $lref = &main::read_file($newv[$i]->{'file'} || $parent->{'file'});
                @nl = &directive_lines($newv[$i], $indent);
                splice(@$lref, $parent->{'line'}+1, 0, @nl);
                $newv[$i]->{'file'} = $parent->{'file'};
                $newv[$i]->{'line'} = $parent->{'line'}+1;
                $newv[$i]->{'eline'} = $parent->{'line'} + scalar(@nl);
                &renumber($parent, $parent->{'line'}, $parent->{'file'}, scalar(@nl));
            }
            splice(@$pm, 0, 0, $newv[$i]);
        }
        elsif ($i >= @newv) {
            # a directive was deleted
            if (!$structonly) {
                local $parent = &get_config_parent($oldv[$i]->{'file'});
                $lref = &main::read_file($oldv[$i]->{'file'});
                $ol = $oldv[$i]->{'eline'} - $oldv[$i]->{'line'} + 1;
                splice(@$lref, $oldv[$i]->{'line'}, $ol);
                &renumber($parent, $oldv[$i]->{'eline'}, $oldv[$i]->{'file'}, -$ol);
            }
            splice(@$pm, &indexof($oldv[$i], @$pm), 1);
        }
        else {
            # updating some directive
            if (!$structonly) {
                local $parent = &get_config_parent($oldv[$i]->{'file'});
                $lref = &main::read_file($oldv[$i]->{'file'});
                @nl = &directive_lines($newv[$i], $indent);
                $ol = $oldv[$i]->{'eline'} - $oldv[$i]->{'line'} + 1;
                splice(@$lref, $oldv[$i]->{'line'}, $ol, @nl);
                $newv[$i]->{'file'} = $parent->{'file'};
                $newv[$i]->{'line'} = $oldv[$i]->{'line'};
                $newv[$i]->{'eline'} = $oldv[$i]->{'line'} + scalar(@nl) - 1;
                &renumber($parent, $oldv[$i]->{'eline'}, $oldv[$i]->{'file'}, scalar(@nl) - $ol);
            }
            $pm->[&indexof($oldv[$i], @$pm)] = $newv[$i];
        }
    }
}

# get_config_parent([file])
# Returns a structure containing the top-level config as members
sub get_config_parent{
    local $file = $_[0] || $main::CONFIG{'BIND_NAMED_CONF'};
    local $conf = &get_config();
    local $lref = &main::read_file($file);
    local $lines_count = @$lref;
    $par_conf =
           { 'file' => $file,
             'type' => 1,
             'line' => -1,
             'eline' => $lines_count,
             'members' => $conf };
    return $par_conf;
}

# directive_lines(&directive, tabs)
sub directive_lines{
    local ($directive, $tabs) = @_;
    local(@rv, $v, $m, $i);
    $rv[0] = "\t" x $tabs;
    $rv[0] .= "$directive->{'name'}";
    foreach $v (@{$directive->{'values'}}) {
        if ($need_quote{$directive->{'name'}} && !$i) {
            $rv[0] .= " \"$v\"";
        }
        else {
            $rv[0] .= " $v";
        }
        $i++;
    }
    if ($directive->{'type'} == 1) {
        # multiple values.. include them as well
        $rv[0] .= " {";
        foreach $m (@{$directive->{'members'}}) {
            push(@rv, &directive_lines($m, $tabs+1));
        }
        push(@rv, ("\t" x ($tabs+1))."}");
    }
    elsif ($directive->{'type'} == 2) {
        # named sub-structures .. include them too
        foreach my $sn (sort { $a cmp $b } (keys %{$directive->{'members'}})) {
            $rv[0] .= " ".$sn." {";
            foreach $m (@{$directive->{'members'}->{$sn}}) {
                $rv[0] .= " ".join(" ", &directive_lines($m, 0));
            }
            $rv[0] .= " }";
        }
    }
    $rv[$#rv] .= ";";
    return @rv;
}

# renumber(&parent, line, file, count)
sub renumber{
    ($parent, $line, $file, $count) = @_;
    if ($parent->{'file'} eq $file) {
        if ($parent->{'line'} > $line) {
            $parent->{'line'} += $count;
        }
        if ($parent->{'eline'} > $line) {
            $parent->{'eline'} += $count;
        }
    }
    if ($parent->{'type'} == 1) {
        # Do sub-members
        local $d;
        foreach $d (@{$parent->{'members'}}) {
            &renumber($d, $line, $file, $count);
        }
    }
    elsif ($parent->{'type'} == 2) {
        # Do sub-members
        local ($sm, $d);
        foreach $sm (keys %{$parent->{'members'}}) {
            foreach $d (@{$parent->{'members'}->{$sm}}) {
                &renumber($d, $line, $file, $count);
            }
        }
    }
}

sub dotted_to_email{
    local $v = $_[0];
    if ($v ne ".") {
        $v =~ s/([^\\])\./$1\@/;
        $v =~ s/\\\./\./g;
        $v =~ s/\.$//;
    }
    return $v;
}

sub email_to_dotted{
    local $v = $_[0];
    $v =~ s/\.$//;
    if ($v =~ /^([^.]+)\@(.*)$/) {
        return "$1.$2.";
    }
    elsif ($v =~ /^(.*)\@(.*)$/) {
        local ($u, $d) = ($1, $2);
        $u =~ s/\./\\\./g;
        return "\"$u.$d.\"";
    }
    else {
        return $v;
    }
}

# indexof(string, array)
# Returns the index of some value in an array, or -1
sub indexof {
    my($i);
    for($i=1; $i <= $#_; $i++) {
        if ($_[$i] eq $_[0]) {
            return $i - 1;
        }
    }
    return -1;
}

# arpa_to_ip(name)
# Converts an address like 4.3.2.1.in-addr.arpa. to 1.2.3.4
sub arpa_to_ip{
    if ($_[0] =~ /^([\d\-\.\/]+)\.in-addr\.arpa/i) {
	return join('.',reverse(split(/\./, $1)));
    }
    return $_[0];
}

# ip_to_arpa(address)
# Converts an IP address like 1.2.3.4 to 4.3.2.1.in-addr.arpa.
sub ip_to_arpa{
    if ($_[0] =~ /^([\d\-\.\/]+)$/) {
	return join('.',reverse(split(/\./,$1))).".in-addr.arpa.";
    }
    return $_[0];
}
1;