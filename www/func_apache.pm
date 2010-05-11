#!/usr/bin/perl
#
# func_apache.pl - functions to deal with apache web server
# Copyright (C) 2008,2009,2010 Alex Amiryan
#
# This file is part of ServerEach
#
# ServerEach is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# ServerEach is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.
#

package apache;

# Return entire httpd parsed config
sub get_config{
    my $conf_path;
    my $rec;
    if ($#_>=0){
	($conf_path, $rec)=@_;
    }
    else{
	$rec=0;
    }
    $conf_path=$main::CONFIG{'APACHE_CONF_PATH'} if(!$conf_path);
    die "Invalid httpd config file given: $!" if(!-f $conf_path);
    
    open(FH, $conf_path) or die "Unable to open $conf_path: $!";
    my $line_num;
    my @conf=&parse_config_file(FH,\$line_num,$conf_path);
    close(FH);

    foreach $inc (&find_directive_struct("Include", \@conf)) {
	my @incs = &parse_apache_include($inc->{'words'}->[0], $main::CONFIG{'APACHE_SERVER_ROOT'});
	foreach my $ginc (@incs) {
            push(@conf, &get_config($ginc,1));
	}
    }
    
    #return ($_[1] ? @conf : \@conf);
    if($rec eq '1'){
	return @conf;
    }
    else{
	return \@conf;
    }
}

# Split words
sub wsplit{
    my ($string, @words, $word);
    $string = $_[0];
    $string =~ s/\\\"/\0/g;
    while($string =~ /^"([^"]*)"\s*(.*)$/ || $string =~ /^(\S+)\s*(.*)$/) {
        $word = $1;
        $string = $2;
        $word =~ s/\0/"/g;
        push(@words, $word);
    }
    return \@words;
}


# find_directive(name, &directives, [1stword])
sub find_directive{
    my($name, $directives, $firstword)=@_;
    my (@vals, $ref);
    foreach $ref (@{$directives}) {
        if (lc($ref->{'name'}) eq lc($name)) {
            push(@vals, $firstword ? $ref->{'words'}->[0] : $ref->{'value'});
        }
    }
    return wantarray ? @vals : !@vals ? undef : $vals[$#vals];
}

# find_directive_struct(name, &directives)
sub find_directive_struct{
    my ($name, $directives) = @_;
    my (@vals, $ref);
    foreach $ref (@{$directives}) {
        if (lc($ref->{'name'}) eq lc($name)) {
            push(@vals, $ref);
        }
    }
    return wantarray ? @vals : !@vals ? undef : $vals[$#vals];
}

# parse_apache_include(dir)
sub parse_apache_include
{
    my ($incdir, $server_root) = @_;
    if ($incdir !~ /^\//) {
        $incdir = "$server_root/$incdir";
    }
    if ($incdir =~ /^(.*)\[\^([^\]]+)\](.*)$/) {
        my $before = $1;
        my $after = $3;
        my %reject = map { $_, 1 } split(//, $2);
        $reject{'*'} = $reject{'?'} = $reject{'['} = $reject{']'} =
        $reject{'/'} = $reject{'$'} = $reject{'('} = $reject{')'} =
        $reject{'!'} = 1;
        local $accept = join("", grep { !$reject{$_} } map { chr($_) } (32 .. 126));
        $incdir = $before."[".$accept."]".$after;
    }
    return sort { $a cmp $b } glob($incdir);
}

# save_directive(name, &values, &parent-directives, &config)
sub save_directive{
    my ($name, $values, $parent_directives, $config) = @_;
    my ($i, @old, $lref, $change, $len, $v);
    @old = &find_directive_struct($name, $parent_directives);
    for($i=0; $i<@old || $i<@{$values}; $i++) {
        $v = ${$values}[$i];
        if ($i >= @old) {
            # a new directive is being added. If other directives of this
            # type exist, add it after them. Otherwise, put it at the end of
            # the first file in the section
            if ($change) {
                # Have changed some old directive.. add this new one
                # after it, and update change
                local(%v, $j);
                %v = (	"line", $change->{'line'}+1,
                        "eline", $change->{'line'}+1,
                        "file", $change->{'file'},
                        "type", 0,
                        "name", $name,
                        "value", $v);
                $j = &indexof($change, @{$parent_directives})+1;
                &renumber($config, $v{'line'}, $v{'file'}, 1);
                splice(@{$parent_directives}, $j, 0, \%v);
                $lref = &main::read_file($v{'file'});
                splice(@$lref, $v{'line'}, 0, "$name $v");
                $change = \%v;
            }
            else {
                # Adding a new directive to the end of the list
                # in this section
                local($f, %v, $j);
                $f = $parent_directives->[0]->{'file'};
                for($j=0; $parent_directives->[$j]->{'file'} eq $f; $j++) { }
                $l = $parent_directives->[$j-1]->{'eline'}+1;
                %v = (	"line", $l,
                        "eline", $l,
                        "file", $f,
                        "type", 0,
                        "name", $name,
                        "value", $v);
                &renumber($config, $l, $f, 1);
                splice(@{$parent_directives}, $j, 0, \%v);
                $lref = &main::read_file($f);
                splice(@$lref, $l, 0, "$name $v");
            }
        }
        elsif ($i >= @{$values}) {
            # a directive was deleted
            $lref = &main::read_file($old[$i]->{'file'});
            $idx = &indexof($old[$i], @{$parent_directives});
            splice(@{$parent_directives}, $idx, 1);
            $len = $old[$i]->{'eline'} - $old[$i]->{'line'} + 1;
            splice(@$lref, $old[$i]->{'line'}, $len);
            &renumber($config, $old[$i]->{'line'}, $old[$i]->{'file'}, -$len);
        }
        else {
            # just changing the value
            $lref = &main::read_file($old[$i]->{'file'});
            $len = $old[$i]->{'eline'} - $old[$i]->{'line'} + 1;
            &renumber($config, $old[$i]->{'eline'}+1, $old[$i]->{'file'},1-$len);
            $old[$i]->{'value'} = $v;
            $old[$i]->{'eline'} = $old[$i]->{'line'};
            splice(@$lref, $old[$i]->{'line'}, $len, "$name $v");
            $change = $old[$i];
        }
    }
}

# save_directive_struct(&old-directive, &directive, &parent-directives,	&config, [firstline-only])
sub save_directive_struct{
    local ($olddir, $newdir, $pconf, $conf, $first) = @_;
    return if (!$olddir && !$newdir);	# Nothing to do
    local $file = $olddir ? $olddir->{'file'} : $newdir->{'file'} ? $newdir->{'file'} : $pconf->[0]->{'file'};
    local $lref = &main::read_file($file);
    local $oldlen = $olddir ? $olddir->{'eline'}-$olddir->{'line'}+1 : undef;
    local @newlines = $newdir ? &get_directive_lines($newdir) : ( );
    if ($olddir && $newdir) {
        if ($first) {
            $lref->[$olddir->{'line'}] = $newlines[0];
            $lref->[$olddir->{'eline'}] = $newlines[$#newlines];
            $olddir->{'name'} = $newdir->{'name'};
            $olddir->{'value'} = $newdir->{'value'};
        }
        else {
            &renumber($conf, $olddir->{'eline'}+1, $file, scalar(@newlines)-$oldlen);
            local $idx = &indexof($olddir, @$pconf);
            $pconf->[$idx] = $newdir if ($idx >= 0);
            $newdir->{'file'} = $olddir->{'file'};
            $newdir->{'line'} = $olddir->{'line'};
            $newdir->{'eline'} = $olddir->{'line'}+scalar(@newlines)-1;
            splice(@$lref, $olddir->{'line'}, $oldlen, @newlines);
            if ($newdir->{'type'}) {
                &recursive_set_lines($newdir->{'members'},
                                           $newdir->{'line'}+1,
                                           $newdir->{'file'});
            }
        }
    }
    elsif ($olddir && !$newdir) {
        splice(@$lref, $olddir->{'line'}, $oldlen);
        local $idx = &indexof($olddir, @$pconf);
        splice(@$pconf, $idx, 1) if ($idx >= 0);
        &renumber($conf, $olddir->{'line'}, $olddir->{'file'}, -$oldlen);
    }
    elsif (!$olddir && $newdir) {
        local ($addline, $addpos);
        if ($newdir->{'file'}) {
            $addline = scalar(@$lref);
            $addpos = scalar(@$pconf);
        }
        else {
            for($addpos=0; $addpos < scalar(@$pconf) && $pconf->[$addpos]->{'file'} eq $file; $addpos++) { }
            $addpos--;
            
            $addline = $pconf->[$addpos]->{'eline'}+1;
        }
        $newdir->{'file'} = $file;
        $newdir->{'line'} = $addline;
        $newdir->{'eline'} = $addline + scalar(@newlines) - 1;
        &renumber($conf, $addline, $file, scalar(@newlines));
        splice(@$pconf, $addpos, 0, $newdir);
        splice(@$lref, $addline, 0, @newlines);

        if ($newdir->{'type'}) {
            &recursive_set_lines($newdir->{'members'},
                                       $newdir->{'line'}+1,
                                       $newdir->{'file'});
        }
    }
}

# recursive_set_lines(&directives, first-line, file)
# Update the line numbers and filenames in a list of directives
sub recursive_set_lines{
    local ($dirs, $line, $file) = @_;
    foreach my $dir (@$dirs) {
        $dir->{'line'} = $line;
        $dir->{'file'} = $file;
        if ($dir->{'type'}) {
            # Do sub-members too
            &recursive_set_lines($dir->{'members'}, $line+1, $file);
            $line += scalar(@{$dir->{'members'}})+1;
            $dir->{'eline'} = $line;
        }
        else {
            $dir->{'eline'} = $line;
        }
        $line++;
    }
    return $line;
}

sub get_directive_lines{
    local @directives=@_;
    local @rv;
    foreach $d (@directives) {
        if ($d->{'type'}) {
            push(@rv, "<$d->{'name'} $d->{'value'}>");
            push(@rv, &get_directive_lines(@{$d->{'members'}}));
            push(@rv, "</$d->{'name'}>");
        }
        else {
            push(@rv, "$d->{'name'} $d->{'value'}");
        }
    }
    return @rv;
}

# renumber(&config, line, file, offset)
sub renumber{
    my ($config, $line, $file, $offset) = @_;
    my ($d);
    if (!$offset) { return; }
    foreach $d (@{$config}) {
        if ($d->{'file'} eq $file && $d->{'line'} >= $line) {
            $d->{'line'} += $offset;
        }
        if ($d->{'file'} eq $file && $d->{'eline'} >= $line) {
            $d->{'eline'} += $offset;
        }
        if ($d->{'type'}) {
            &renumber($d->{'members'}, $line, $file, $offset);
        }
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

# parse_config_file(handle, lines, file, [recursive])
# Parses lines of text from some config file into a data structure. The
# return value is an array of references, one for each directive in the file.
# Each reference points to an associative array containing
#  line -	The line number this directive is at
#  eline -	The line number this directive ends at
#  file -	The file this directive is from
#  type -	0 for a normal directive, 1 for a container directive
#  name -	The name of this directive
#  value -	Value (possibly with spaces)
#  members -	For type 1, a reference to the array of members
sub parse_config_file{
    my($handle, $line_num, $file, $recursive)=@_;
    local($fh, @rv, $line);
    $fh = $handle;
    ##$$line_num=0 if undef($$line_num);
    while($line = <$fh>) {
        chomp($line);
        $line =~ s/^\s*#.*$//g;
        if ($line =~ /^\s*<\/(\S+)\s*(.*)>/) {
            # end of a container directive.
            $$line_num++;
            last if (lc($recursive) eq lc($1));
        }
        elsif ($line =~ /^\s*<(\S+)\s*(.*)>/) {
            # start of a container directive.
            local(%dir, @members);
            %dir = ('line', $$line_num,
                    'file', $file,
                    'type', 1,
                    'name', $1,
                    'value', $2);
            $dir{'value'} =~ s/\s+$//g;
            $dir{'words'} = &wsplit($dir{'value'});
            $$line_num++;
            @members = &parse_config_file($fh, $line_num, $file, $dir{'name'});
            $dir{'members'} = \@members;
            $dir{'eline'} = $$line_num-1;
            push(@rv, \%dir);
        }
        elsif ($line =~ /^\s*(\S+)\s*(.*)$/) {
            # normal directive
            local(%dir);
            %dir = ('line', $$line_num,
                    'eline', $$line_num,
                    'file', $file,
                    'type', 0,
                    'name', $1,
                    'value', $2);
            if ($dir{'value'} =~ s/\\$//g) {
                # multi-line directive!
                while($line = <$fh>) {
                    chomp($line);
                    $cont = ($line =~ s/\\$//g);
                    $line=~s/^\s*//;
                    $dir{'value'}=~s/\s*$//;
                    $dir{'value'} .= " $line";
                    $dir{'eline'} = ++$$line_num;
                    if (!$cont) {
                        last;
                    }
                }
            }
            $dir{'value'} =~ s/\s+$//g;
            $dir{'words'} = &wsplit($dir{'value'});
            push(@rv, \%dir);
            $$line_num++;
        }
        else {
            # blank or comment line
            $$line_num++;
        }
    }
    return @rv;
}
1;