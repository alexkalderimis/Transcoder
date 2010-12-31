use MooseX::Declare;

class Transcoder::CD::Span {

    use Carp qw/confess/;
    use constant SPAN_VALIDATOR => 
        m{ ^ # nothing before
            ( 
                -       # either a single dash or... 
                |                          
                (
                    [0-9]+ -    # a lower boundery open group or ..
                    |                   
            # An initial group (with optional lower bound)
                    ([0-9]*-)?[0-9]+            
            # As many intermediate groups as are wished for
                    ( , [0-9]+(- [0-9]+  )? )*  
            # And a final group (with optional upper bound)
                    ( , [0-9]+(-([0-9]+)?)? )?
                )
            )
            $ # and nothing after
        }x;

    has 'contained_members' => (
        isa => 'ArrayRef[Int]',
        is => 'ro',
        traits => [qw/Array/],
        handles => {
            add_member => 'push',
            get_track_numbers => 'elements'
            grep_members => 'grep',
        },
    );

    has string => (
        isa => 'Str',
        is => 'ro',
        required => 1,
    );

    has total_tracks => (
        isa => 'Int',
        is => 'ro',
        required => 1,
    );

    method is_contained_member(Int $index) {
        return $self->grep_members(sub {$_ eq $index});
    }

    method BUILD {
        confess "Bad span (does not validate)", $self->string;
            unless ($self->string =~ $self->SPAN_VALIDATOR);
        my @spans = split(/,/, $self->string);
        my %tracks;
        my $bad;
        foreach (@spans) { 
            # where the group is x-y, add every no 
            # in that range to the list of tracks to rip
            if (/(\d+)-(\d+)/) {
                if ($1 > $2) {
                    confess "Bad span: ", $self->string,
                    " :span section ' $_ ' wrong way round";
                } else {
                    foreach my $i ($1 .. $2) {
                        $tracks{$i}++;
                    }
                }
            # where the group is -x, add every no 
            # from 1 to x to the list of tracks to rip
            } elsif (/^-(\d+)$/) { 
                foreach my $i (1 .. $1) {
                    $tracks{$i}++;
                }
            # where the group is x-, add every no from
            # x to the last track to the list of tracks to rip
            } elsif (/^(\d+)-$/) { 
                if ($1 > $self->get_total_tracks) {
                    confess "Bad span: ", $self->string,
                    " :span section ' $_ ' extends beyond last track";
                } else {
                    foreach my $i ($1 .. $last) {
                        $tracks{$i}++;
                    }
                }
            # where the group is -, add every track to the list
            # of tracks to rip
            } elsif (/^-$/) {      
                foreach my $i (1 .. $last) {
                    $tracks{$i}++;
                }
            } elsif (/^\d+$/) { 
            # Where is is just a track number, add it to the list
                $tracks{$_} ++;
            } else {
                confess "Bad span: ", $self->string,
                " I don't know what this span section is: $_";
            }
        }
        foreach (sort { $a <=> $b } keys(%tracks)) {
            $self->add_member($_);
        }
    }

}
