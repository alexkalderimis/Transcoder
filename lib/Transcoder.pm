use MooseX::Declare;

class Transcoder {

    use Modern::Perl;
    use MooseX::FollowPBP;

    has 'tracks' => (
        isa         => 'HashRef[Transcoder::Track]',
        predicate   => "has_tracks",
        default     => sub { {} },
    );
    has 'tracks_to_rip' => (
        traits => ['Array'],
        isa => 'ArrayRef[Transcoder::Track]',
        default => sub { [] },
        auto_deref => 1,
        handles => {
            add_track_to_rip => 'push',
            get_number_of_tracks_to_rip => 'count',
        },
    )
    has 'services' => (
        is => 'rw',
        isa => 'ArrayRef',
        lazy => 1,
        default => sub {["freedb.freedb.org", "freedb.musicbrainz.org"]}
    );
    has 'verbosity' => (
        is => 'ro',
        isa => 'Int',
        default => 0,
    );
    has 'bitrate' => (
        is => 'ro',
        isa => 'Int',
        default => 50,
    );
    has 'force' => (
        isa => 'Bool', 
        is => 'ro', 
        lazy_build => 1
    );

    method _build_force() {
        return 0;
    }
    
    method transcode() {
        my $current = 1;
        my $total = $self->get_number_of_tracks_to_rip;
        my $success_count;
        my @problems;
        for my $track ($self->get_tracks_to_rip) {
            say ('-' x 20);
            my $was_success = $track->encode($current++, $total);
            if ($was_success) {
                $success_count++;
            } else {
                push @problems, $track->get_encoding_problem;
            }
        }
        printf "%d new files, %d source files not encoded\n", 
                $success_count, scalar(@problems);
        if (@problems) {
            say "Encountered problems: ", join(', ', @problems);
        }
        return;
    }

}



