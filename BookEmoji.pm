package BookEmoji;

use JSON::Syck;
use YAML::Syck;

sub new {
    my $classname = shift;    # What class are we constructing?
    my %hash = @_;
    my $self      = \%hash;       # Allocate new memory
    bless( $self, $classname );    # Mark it of the right type
    $self->_init(@_);              # Call _init with remaining args
    return $self;
}

sub _init {

    my ( $self) = @_;
    
    $self->{file} ||= "emoji-data/emoji_pretty.json";
    my $data = JSON::Syck::LoadFile($self->{file}) or die "could not open file $self->{file}: $!  (perhaps you should ' git submodule add https://github.com/iamcal/emoji-data.git')";

    my %short;
    
    foreach my $href (@{$data}) {
      if ($href->{unified}) {
        $href->{short_names} ||= [];
        foreach my $key ($href->{short_name},@{ $href->{short_names}}){
           my($a,$b) = split(/-/,$href->{unified});
           $short{$key} ||= chr(hex($a));
        }
      }
    }
    
    $self->{short} = \%short;
    $self->{names} = [sort keys %short];
    
    my @escaped = map("\Q$_",@{$self->{names}});
    my $joined = join("|",@escaped);
    my $re = qr/(:(?:$joined):)/;
    
    
    
    $self->{re} = $re;
    
    return $self;
} ## end sub _init

sub names {
  my $self = shift;
  return @{$self->{names}};
}
sub char { 
 my $self= shift;
 my $name = shift;
 if ($name =~ /^:(.*):$/) {
   $name = $1;
 }
 if (exists $self->{short}{$name}) {
   return $self->{short}{$name};
 } 
 return;
}


1;
