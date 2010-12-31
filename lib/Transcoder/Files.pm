use MooseX::Declare;

class Transcoder::Files extends Transcoder {

    use MooseX::FollowPBP;

    use constant 'FILE_FORMATS' => qr/\.(m4a|mp3|ogg|flac|wma)$/i;

    method _build_tracks {
        for my $file ($self->get_files) {
            next unless (-f $file and $file =~ $self->FILE_FORMATS);
            my $track = Transcoder::Track->new($file);
            $self->add_to_tracks($track);
        }
    }
}
