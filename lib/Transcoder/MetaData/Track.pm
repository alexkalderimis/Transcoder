use MooseX::Declare;

class Transcoder::MetaData::Track extends Transcoder::MetaData {
    
    use MooseX::FollowPBP;

    has 'album' => (
        isa => 'Transcoder::MetaData::Album',
        is => 'rw',
        lazy_build => 1,
    );

    has [qw/number src_bitrate/] => (
        isa => 'Int',
        is => 'rw',
        lazy_build => 1,
    );

    has [qw/minutes seconds frames/] => (
        isa => 'Int'
        is => 'rw',
        coerce => 1,
    );

    has 'is_audio' => (
        isa => 'Bool', 
        is => 'rw',
        default => 1,
    );

    method _build_title {
        return "TRACK " . $self->number;
    }


}
