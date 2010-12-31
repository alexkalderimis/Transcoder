use MooseX::Declare;

class Transcoder::MetaData {

    use Transcoder::MetaData::Album;
    use Transcoder::MetaData::Track;
    use MooseX::FollowPBP;
    use DateTime::Format::Flexible;
    use MooseX::FileAttribute;

    has ['artist', 'title','genre'] => (
        isa => 'Str',
        is => 'rw',
        lazy_build => 1,
    );

    has date => (
        isa => 'DateTime',
        coerce => 1,
        is => 'rw',
        lazy_build => 1,
    );

    has art => (
        is => 'rw',
        lazy_build => 1,
    );

    has_file art_file => (
        is => 'rw',
        lazy_build => 1,
    );

    has_dir 'destination_dir' => (
        is => 'rw',
        lazy_build => 1,
    );

    method new_album_info() {
        return Transcoder::MetaData::Album->new();
    }

    method new_track_info() {
        return Transcoder::MetaData::Track->new();
    }


}
