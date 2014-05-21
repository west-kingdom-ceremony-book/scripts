package BookLib;

use Getopt::Long qw(GetOptionsFromArray);
use URI::Encode qw(uri_decode uri_encode);
use YAML::Syck;
use YAML::Syck;
use Net::GitHub;
use IO::File;
use IO::Dir;
use File::Slurp;
use Digest::MD5 qw(md5_hex);
use HTML::Entities;
use Encode qw(encode_utf8 decode_utf8);
use LWP::UserAgent;
use BookEmoji;
use strict;
use utf8;


sub new {
    my $classname = shift;    # What class are we constructing?
    my $self      = {};       # Allocate new memory
    bless( $self, $classname );    # Mark it of the right type
    $self->_init(@_);              # Call _init with remaining args
    return $self;
}

sub _init {

    my ( $self, $aref, $href ) = @_;

    $self->{input} = {
                       "c|config=s"   => "config file (required)",
                       "u|userinfo=s" => "user info",
                       "v|verbose"    => "spew extra data to the screen",
                       "h|help"       => "show option help"
                     };

    if ($href) {
        foreach my $key ( keys %$href ) {
            $self->{input}{$key} = $href->{$key};
        }
    }

    $self->{argv} = {};

    my $result = GetOptionsFromArray( $aref, $self->{argv}, keys %{ $self->{input} } );
    if ( ( !$result ) || ( $self->{argv}{h} ) ) {
        $self->showOptionsHelp();
        exit 0;
    }
    $self->{argv}{c} ||= "config.yaml";
    $self->{argv}{u} ||= "user.yaml";

    $self->{c} = LoadFile( $self->{argv}{c} );
    $self->{u} = LoadFile( $self->{argv}{u} );

    system( "mkdir", "-p", $self->cachedir(), $self->htmldir() );

    $self->{images} = {};    # Image cache

    return $self;
} ## end sub _init

sub token {
    my $self = shift;
    return $self->{u}{token};
}

sub showOptionsHelp {
    my $self = shift;
    my ( $left, $right, $a, $b, $key );
    my (@array);
    my %hash = %{ $self->{input} };
    print "Usage: $0 [options]\n";
    print "where options can be:\n";
    foreach $key ( sort keys(%hash) ) {
        ( $left, $right ) = split( /[=:]/, $key );
        ( $a,    $b )     = split( /\|/,   $left );
        if ($b) {
            $left = "-$a --$b";
        } else {
            $left = "   --$a";
        }
        $left = substr( "$left" . ( ' ' x 20 ), 0, 20 );
        my $help = $hash{$key};
        push( @array, "$left $help\n" );
    }
    print sort @array;
} ## end sub showOptionsHelp

sub title_to_filename {
    my $self = shift;
    my ($s) = @_;

    # Convert a wiki page name to a filename
    # yuck.
    
    # If there is a "|" in the name, that is really 
    # a seperator between FanctText and PageName.
    $s =~ s#.*\|##;
    
    # Space to dashes
    $s =~ s/ /-/g;
    
    # Dangerous characters to CGI encoded
    $s = uri_encode( $s, { encode_reserved => 1 } );
    
    # Some should not be converted. Convert back.
    $s =~ s/%27/'/g;
    $s =~ s/%28/(/g;
    $s =~ s/%29/)/g;
    

    print "s=$s\n" if ( $self->{argv}{"v"} );

    return $s;
}

sub filename_to_title {
    my $self = shift;
    my ($s) = @_;
    $s = uri_decode($s);
    $s =~ s/-/ /g;
    $s=decode_utf8($s);
    return $s;
}

sub wiki_links {
    my $self = shift;
    my ($s) = @_;
    my (@links) = ( $s =~ m/\[\[[^\]]+\]\]/msg );
    @links = map( substr( $_, 2, -2 ), @links );
    return @links;
}

sub get_title_from_md {
    my $self = shift;
    my ($text) = @_;
    if ( $text =~ /^#+([^#\n]+)/msg ) {
        my $return = $1;
        $return =~ s/^\s+//;
        $return =~ s/\s+$//;
        return $return;
    } else {
        return "";
    }
}

sub expand_name {
    my $self    = shift;
    my $key     = shift;
    my $default = shift;
    my $top     = $self->{c}{paths}{topdir} || ".";
    my $value   = $self->{c}{paths}{$key} || $default || $key;
    return ( $value =~ m#^/# ) ? $value : "$top/$value";
}

sub wikidir {
    my $self = shift;
    return $self->expand_name("wikidir");
}

sub cachedir {
    my $self = shift;
    return $self->expand_name("cachedir");
}

sub epubfile {
    my $self = shift;
    my $name = $self->expand_name("epubfile");
    $name .= ".epub" unless ( $name =~ m#\.epub$#i );
    return $name;
}

sub htmldir {
    my $self = shift;
    return $self->expand_name("htmldir");
}

sub OEBPS {
    my $self = shift;
    return $self->htmldir . "/OEBPS";
}

sub templatedir {
    my $self = shift;
    return $self->expand_name("templatedir");
}

# $self->files(dir,ext)
# returns list of files in dir, with ext removed
sub files {
    my $self  = shift;
    my $dir   = shift;
    my $ext   = shift;
    my @found = read_dir($dir);
    my @return;
    foreach (@found) {
        if ($ext) {
            if ( substr( $_, 0 - length($ext) ) eq $ext ) {
                substr( $_, 0 - length($ext) ) = "";
                push( @return, $_ );
            }
        } else {
            push( @return, $_ );
        }
    }
    return @return;
}

# Returns list of wiki files (not titles)
sub wikifiles {
    my $self = shift;
    return $self->files( $self->wikidir, ".md" );
}

# $self->title_exists("title")
# returns true if a wiki file exists with the right filename for a given title
sub title_exists {
    my $self     = shift;
    my $title    = shift;
    
    my $name     = $self->title_to_filename($title);
    my $filename = $self->wikidir . "/" . $name . ".md";
    return -s $filename;
}

# $self->gh
# returns (possibly cached) handle to GitHub
sub gh {
    my $self = shift;
    $self->{gh} ||= $self->get_new_gh();
    return $self->{gh};
}

# $self->get_new_gh
# returns handle to GitHub
sub get_new_gh {
    my $self  = shift;
    my $token = shift || $self->token;
    my $gh    = Net::GitHub->new( version => 3, raw_response => 1, access_token => $token ) or die;
    return $gh;
}

# $self->read_md(title)
# returns the wiki file for "title"
sub read_md {
    my $self     = shift;
    my $name     = shift;
    my $filename = $self->title_to_filename($name);
    my $fullname = $self->wikidir() . "/" . $filename . ".md";
    if ( -f $fullname ) {
        my $blob = read_file( $fullname, { binmode => ':utf8' } );
        return $blob;
    } else {
        warn "Could not fine $fullname (title: $name) ";
        return "";
    }
}

# $self->markdown_to_html(text)
# returns html  (possibly cached; possibly calls GitHub API /markdown)
sub markdown_to_html {
    my $self     = shift;
    my $markdown = shift;
    my $fixlinks = shift || 0;
    my $converting = shift || "unspecified markdown_to_html()";
    my $cachedir = $self->cachedir();
    
    
    
    
    
    my $digest   = md5_hex( encode_utf8($markdown) );

    if ($fixlinks) {
        my @links = $self->wiki_links($markdown);
        foreach my $title (@links) {
        
         # XXX
            my ($left,$right) = split(m#[|]#,$title);
            $right ||= $left;  # If not "Nice Page|NicePage" then default right side to exactly match left
            
            my $title_e = encode_entities($title);  # ? Why do we have this?
            my $replace = "[[$title]]";
            my $with;
            

            if ( $self->title_exists($title) ) {
                $with = "[$left]" . "(" . $self->title_to_filename($title) . ".html" . ")";
            } else {
                $with = "~~$title~~";
                print "WARNING: Found bad reference to [[$title]] in [[$converting]]\n";
            }

            $markdown =~ s/\Q$replace/$with/gsm;
        }
    }

    my $cachename = $cachedir . "/" . $digest . ".cache";    # TODO do we need to shard directories?

    if ( -f $cachename ) {
        my $return = read_file( $cachename, binmode => ':utf8' );
        return $return;
    } else {
        my $return = $self->github_markdown($markdown);
        write_file( $cachename, { binmode => ":utf8" }, $return );
        return $return;
    }
} ## end sub markdown_to_html

sub cleanup_html {
    my $self = shift;
    my $s    = shift;
    $s =~ s#<br>#<br />#g;
    $s =~ s#<hr>#<hr />#g;

    
    # Screw it.  Just remove the generated anchor points.  We're not using them.
    # If we want them back, then we must about stuff like accent marks in ids.
    $s =~ s#(\n*<a name="user-content-([^"]+)" class="anchor" href="\#\2">\s*<span[^>]+>\s*</span></a>)##mg;
      

    # <a name=... > needs to be <a id=..>
    $s =~ s#<a name="user-content-([^"]+)" class="anchor" href="\#\1">#<a id="$1" class="anchor" href="\#$1">#gsm;

    return $s;
}

sub classify_blockquotes {
  my $self = shift;
  my $html = shift;
  my @html = split(/\n/,$html);
  foreach my $i (2 .. (scalar @html-1)) {
     if ($html[$i] =~ /<blockquote>/) {
     
       my $check = $html[$i-2];
       print "CHECK: $check\n";
       if ($check =~ /:star:/) {
         $html[$i] =~ s/<blockquote>/<blockquote class="graybox">/;
       }
       if ($check =~ /\bOPTIONAL\b/) {
         $html[$i] =~ s/<blockquote>/<blockquote class="graybox">/;
       }
       if ($check =~ /⭐ /i) {
       #  ⭐
         $html[$i] =~ s/<blockquote>/<blockquote class="graybox">/;
       }
       if ($check =~ /\b(king|crown)\b/i) {
         $html[$i] =~ s/<blockquote>/<blockquote class="crown">/;
       }
       if ($check =~ /\b(queen|rose)\b/i) {
         $html[$i] =~ s/<blockquote>/<blockquote class="rose">/;
       }
       if ($check =~ /\bherald\b/i) {
         $html[$i] =~ s/<blockquote>/<blockquote class="herald">/;
       }
     }
    
  }
  return join("\n",@html,"");  
}


sub localize_images {
    my $self = shift;
    my $s    = shift;
    $s =~ s#(<img [^>]+>)# $self->_localize_images_helper($1) #ge;
    return $s;
}

sub _localize_images_helper {
    my $self  = shift;
    my $input = shift;


# <img class="emoji" title=":star:" alt=":star:" src="7a4d1dbbe90af05db5854333d5908e8b.png" height="20" width="20" />
# Lets .. replace that with an emoji.

    if ($self->{c}->{options}->{unicode}) {
  
        if ($input =~ /img class="emoji" title=":(.*?):" alt=":\1:"/) {
          my $name = $1;
          $self->{emoji} ||= new BookEmoji;
          my $e = $self->{emoji}->char($name);
          print "Emoji used! $e\n";
          return $e if ($e);  # Only if we found an emoticon that matched. Otherwise, leave the image in place.
        }

    }    


    # Just get rid of this; does not validate against epub
    $input =~ s#align="absmiddle"##;
    $input =~ s#([^/])>$#$1/>#;        # Close image tag

    if ( $input =~ m#src="([^"]+)"# ) {
        my $url = $1;

        # Get it.  It might be already nearby anyways.
        my ( $base64, $type, $extension ) = $self->mirror_content($url);

        # Change the url to a local reference.
        my $newurl = "$base64\.$extension";


        my $search = "\Q$url";
        $input =~ s#$search#$newurl#;

    }
    return $input;
} ## end sub _localize_images_helper

sub mirror_content {
    my $self      = shift;
    my $url       = shift;
    my $base64    = md5_hex($url);
    my $cachefile = $self->cachedir . "/$base64.content";
    my $typefile  = $self->cachedir . "/$base64.type";

    # Found it on this run already.
    if ( exists $self->{images}{$url} ) {
        return @{ $self->{images}{$url} };
    }

    # Disk cache still has the previous run, reuse it.
    if ( -f $self->cachedir . "/$base64.content" ) {
        my $type = read_file($typefile);
        my ( $x, $extension ) = split( m#/#, $type );
        $self->{images}{$url} = [ $base64, $type, $extension ];
        return @{ $self->{images}{$url} };
    }

    # Go fetch whatever this thing is.
    my $ua = LWP::UserAgent->new;
    $ua->agent("$0/0.1");
    my $req = HTTP::Request->new( GET => $url );
    my $res = $ua->request($req);
    if ( $res->is_success ) {

        # Decode and store locally on disk for next time
        my $content = $res->decoded_content || $res->content;
        my $type = $res->header("Content-Type");
        write_file( $typefile,  $type );
        write_file( $cachefile, $content );

        # Update memory cache, return info
        my ( $x, $extension ) = split( m#/#, $type );
        $self->{images}{$url} = [ $base64, $type, $extension ];
        return @{ $self->{images}{$url} };

    } else {
        print STDER "Error: " . $res->status_line . "\n";
        exit 1;
    }

} ## end sub mirror_content

# sub github->markdown(text)
# returns converted text to html
# without caching, wihout fixing,
# just a straight GitHub API /markdown call.
sub github_markdown {
    my $self     = shift;
    my $markdown = shift;
    my $gh       = $self->gh();
    $markdown = encode_utf8($markdown);    #BAD IDEA
    my $response = $gh->query( "POST", "/markdown", { text => $markdown, mode => "markdown" } );
    if ( $response->is_success ) {
        my $return = $response->decoded_content || $response->content;
        $return = decode_utf8($return);
        my $r = $response->header("x-ratelimit-remaining");
        print STDERR "max remaining $r\n";
        return $return;
    } else {
        print STDERR "failed to convert using github API /markdown ..\n";
        print STDERR $response->status_line, "\n";
        exit 1;
    }
}

# $self->find_all_links()
# Shows what links are in a given file (default ToC)
sub find_all_links {
    my $self  = shift;
    my $name  = shift || "ToC";
    my $toc   = $self->read_md($name);
    my @links = $self->wiki_links($toc);
    return @links;
}

# $self->find_good_links()
# Shows what links point to valid files in a given file (default ToC)
sub find_good_links {
    my $self  = shift;
    my @links = $self->find_all_links(@_);
    @links = grep( $self->title_exists($_), @links );
    return @links;
}

# $self->find_bad_links()
# Shows what links point to missing files in a given file (default ToC)
sub find_bad_links {
    my $self  = shift;
    my @links = $self->find_all_links(@_);
    @links = grep( $self->title_exists($_), @links );
    return @links;
}

# $self->find_orphan_links()
# Shows what wiki files we can find, that aren't linked in file (default ToC)
sub find_orphan_links {
    my $self  = shift;
    my @links = $self->find_all_links(@_);
    my @names = map ( $self->title_to_filename($_), @links );
    my @have  = $self->wikifiles();

    my %names = map { $_ => 1 } @names;
    my @orphan = grep( !exists $names{$_}, @have );
    return @orphan;
}

sub create_better_toc {
    my $self     = shift;
    my @orphan   = $self->find_orphan_links;
    my $original = $self->wikidir() . "/ToC.md";
    my $better   = $self->wikidir() . "/BetterToC.md";
    my $blob     = read_file( $original, { binmode => ':utf8' } );
    my $compare = (-f $better) ? read_file( $better, { binmode => ':utf8' } ) : "";
    
#    @orphan = grep(! m/^(ToC|BetterToC|Home)$/, @orphan);

    # Append anything orphan.
    if (@orphan) {
        $blob .= "\n\nOther Wiki Pages (Not Organized)\n";
        foreach my $filename (@orphan) {
            next if ($filename eq "Home");
            next if ($filename eq "ToC");
        
           print "Orphan: $filename\n";
           
            my $title = $self->filename_to_title($filename);
            my $better = $self->get_title_from_md($self->read_md($title));
            if ($better ){
              $blob .= "* [[$better|$title]]\n";
            } else {
              $blob .= "* [[$title]]\n";
            }
        }
        $blob .= "\n";
    }

    # Only rewrite, if the file changed.
    if ( $blob ne $compare ) {
        write_file( $better, { binmode => ":utf8" }, $blob );
    }
    return;
} ## end sub create_better_toc

sub scan_better_toc {
    my $self = shift;
    my $name = shift || "BetterToC";
    my @good = $self->find_good_links($name);
    my @bad  = $self->find_bad_links($name);

    %{ $self->{good} } = map { $_ => 1 } @good;
    %{ $self->{bad} }  = map { $_ => 1 } @bad;

}

sub scan_toc_for_ncx {
    my $self = shift;
    my $name = shift || "BetterToC";

    my @return;

    my $toc = $self->read_md($name);
    my @toc = split( /\n/, $toc );
    die "missing $name" unless ($toc);

    my %titles;

    foreach my $line (@toc) {
        next unless ( $line =~ /\S/ );    # Remove empty lines
        next if ( $line =~ /^#/ );        # Remove headings

        $line =~ s/\*\*//g;               # Remove bolds

        # Find out how much indentation there is; and remove it
        my $indent = 0;
        if ( $line =~ m#^([ ]*[*])# ) {
            $indent = length($1);
            substr( $line, 0, $indent ) = "";
        }

        # Determine if we specify a link
        my $text = $line;
        my $link;
        if ( $line =~ m#\[\[([^\]]+)\]\]# ) {
            $link = $1;
            $text = $1;
            if ($text =~ m#[|]#) {
              ($text,$link) = split(m#[|]#,$text);
            }
        }
        

        # If indented, and not a link, skip it.
        next if ( ($indent) && ( !$link ) );

        # Skip broken links
        next if ( ($link) && ( !$self->title_exists($link) ) );

        # Pad the text to fake indentation
        if ($indent) {
            my $n = "";
            $n .= ". " foreach ( 1 .. $indent );
            $text = $n . $text;
        }

        # Clean up whitespace
        $text =~ s/^\s+//;
        $text =~ s/\s+$//;

        push( @return, [ $link, $text ] );
    } ## end foreach my $line (@toc)

    # Any text that is missing a link:
    # link to the following page.
    # TO do that we will scan the list in
    # reverse, always tracking the last known
    # page; and assigning it to the blanks.
    my $lastlink = "unknown";
    foreach my $aref ( reverse @return ) {
        $aref->[0] ||= $lastlink;    # Fill if blank
        $lastlink = $aref->[0];      # And copy for the next time around
    }

    # We're done.   Returns arrays of [link,text]
    return @return;
} ## end sub scan_toc_for_ncx

1;
