#!/usr/bin/perl

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