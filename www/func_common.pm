#!/usr/bin/perl
#
# func_common.pl - common functions for ServerEach
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

# Read Web Server Configurator config
sub read_conf{
    open(CNF,"config.conf") or die "Unable to open config file: $!";
    foreach my $line (<CNF>){
        if($line=~/^([\w_]*)\s*=\s*?(['"])(.+)\2$/){
            $CONFIG{$1}=$3;
        }
        elsif($line=~/^\s*$/){
            next;
        }
        else{
            die "Syntax error in config near \"$line\"";
        }
    }
    close CNF;
}

# read_file(file)
# Returns a reference to an array containing the lines from some file. This
# array can be modified, and will be written out when save_files()
# is called.
sub read_file{
    my $file=shift;
    if (!$file) {
        local ($package, $filename, $line) = caller;
        print STDERR "Missing file to read at ${package}::${filename} line $line\n";
    }
    if (!$file_cache{$file}) {
        my(@lines, $eol);
        open(READFILE, $file);
        while(<READFILE>) {
            if (!$eol) {
                $eol = /\r\n$/ ? "\r\n" : "\n";
            }
            tr/\r\n//d;
            push(@lines, $_);
        }
        close(READFILE);
        $file_cache{$file} = \@lines;
    }
    return $file_cache{$file};
}

# save_files([file])
sub save_files{
    $file=shift;
    my @files;
    if ($file) {
        $file_cache{$file} || die "File '$file' is not loaded";
        push(@files, $file);
    }
    else {
        @files = ( keys %file_cache );
    }
    foreach my $f (@files) {
        open(FLUSHFILE, ">$f") || die "Can't open file '$f': $!";
        foreach my $line (@{$file_cache{$f}}) {
            (print FLUSHFILE $line,"\n") ||  die "Can't write to file '$f': $!";
        }
        close(FLUSHFILE);
        delete($file_cache{$f});
    }
}

sub error{
    $msg=shift;
    &html::get_header();
    print <<EOF;
    <pre class="red">$msg</pre><br>
    <input type="button" onclick="history.go(-1)" value="<--Back">
EOF
    exit 0;
}

sub split_by_nl{
    my @vals = split(/[\r\n]{1,2}/,$_[0]);
    return \@vals;
}

# in_array(needle, stock)
sub in_array{
    my ($needle, $stock) = @_;
    foreach $item ($stock){
        if($item eq $needle){
            return 1;
        }
    }
    0;
}

# unique
# Returns the unique elements of some array
sub unique{
    local(%found, @rv, $e);
    foreach $e (@_) {
	if (!$found{$e}++) { push(@rv, $e); }
    }
    return @rv;
}
1;