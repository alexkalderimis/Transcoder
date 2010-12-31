use MooseX::Declare;

class Transcoder::MetaData::Album extends Transcoder::MetaData {

    has 'is_multiple_artists' => (
        isa => 'Bool',
        is => 'rw',
        traits => [qw/Bool/],
        handles => {
            set_multiple_artists => 'set',
            set_single_artist    => 'unset',
        },
        default => 1,
    );

    method _build_title {
        return "ALBUM TITLE";
    }
    method _build_artist {
        return "ALBUM ARTIST";
    }
    method _build_genre {
        return "UNKNOWN";
    }

}
