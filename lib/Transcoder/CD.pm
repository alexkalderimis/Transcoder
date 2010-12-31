use MooseX::Declare;

class Transcoder::CD extends Transcoder {

    use Moose::Util::TypeConstraints;
    use MooseX::FollowPBP;
    use CDDB_get qw( get_cddb );
    use Encode;
    use Net::Ping;
    use Net::Ping::External;
    use Log::Handler;
    use Linux::CDROM;

    method _build__span {
        return Transcoder::CD::Span->new(
            string => $self->get_span,
            total_tracks => $self->get_last_track_number,
        );
    }

    has '_span' => (
        is => 'rw',
        isa => 'Transcoder::CD::Span'
        default => '-',
        lazy_build => 1,
        handles => {
            tracks_in_span => 'get_contained_members',
            is_in_span => 'is_contained_member',
        },
    );

    has 'span' => (
        isa => 'Str',
        is => 'ro',
        default => '-',
    );

    has 'metadata' => (
        isa => 'Transcoder::MetaData';
        is => 'ro',
        lazy_build => 1,
    }

    has 'logger' => (
        isa => 'Log::Handler',
        handles => [qw/debug info error warning/],
        lazy_build => 1,
    );

    has 'tracks' => (
        isa => 'ArrayRef[Transcoder::Track]',
        is => 'ro',
        traits => [qw/Array/],
        auto_deref => 1,
        handles => {
            add_track => 'push',
            set_track => 'set',
            get_track => 'get',
            get_total_tracks => 'count',
        },
    );

    has 'last_track_number' => (
        isa => 'Int',
        is => 'rw',
    );

    has 'services' => (
        is => 'rw', 
        isa => 'ArrayRef', 
        lazy => 1,
        default => sub {["freedb.freedb.org", "freedb.musicbrainz.org"]}
    );

    method _build_logger {
        return Log::Handler->get_logger('Transcoder');
    }

    method _build_info {
        return Transcoder::MetaData->new_album_info;
    }

    method _get_data(Str $service) {
    
        my (%cdinfo, %config);
        $config{CDDB_HOST}=$s;
        $config{CDDB_MODE}="http" if ($s =~ /brainz/);
    
        # user interaction welcome?
        $config{input}= 0; # 1: ask user if more than one possibility
                           # 0: no user interaction
    
        %cdinfo = $self->query_service($service);

        # if query fails try a different service
        unless (defined $cdinfo{title}) { 
            $self->info("Disc not found at $s, moving along");
        } else {
            $self->set_metadata(\%cdinfo);
        }
        return;
    }

    method query_service(Str $service) {
        $self->info("Checking internet connection to $service ...");
        # check the net is up 
        # otherwise cddb_get.pm dies on us
        my $p = Net::Ping->new('external'); 
                                            
        if ( $p->ping($service) ) { 
            $self->info("Querying $service ...");
            # query cddb for disc information
            # Has keys: track, tno, frames, data, genre
            # artist, cat, revision, id, title, year, raw
            %cdinfo=get_cddb(\%config); 
            if ($service =~ /db\.org/) {
                my %newcdinfo = map { $_ => encode_utf8($cdinfo{$_})} 
                                ("artist", "title", "genre", "year");
                foreach (@{$cdinfo{track}}) {
                    push @{$newcdinfo{track}}, encode_utf8($_);
                }
                %cdinfo = %newcdinfo;
            }
            return %cdinfo;
        } else {
            $self->error("Could not connect to $s");
            return;
        }
    }

    method set_metadata(HashRef $cdinfo) {
        $self->debug("CD info: ", Dumper($cdinfo));
        if ( $cdinfo{artist} =~ /^various/i ) {
            $self->get_metadata->set_multiple_artists();
        }
        $self->debug("setting artist as $cdinfo{artist}");
        $self->get_metadata->set_artist(cdinfo{artist});
        $self->debug("setting title as $cdinfo{title}");
        $self->get_metadata->set_title($cdinfo{title});
        $self->debug("setting genre as $cdinfo{genre}");
        $self->get_metadata->set_genre($cdinfo{genre} || "unknown");
        $self->debug("setting date as $cdinfo{year}");
        $self->get_metadata->set_date( $cdinfo{year} || "unknown");
        foreach ( 1 .. $self->total_tracks ) {
            my $artist = $self->get_metadata->get_artist 
            my $title = ${$cdinfo{track}}[($_-1)];
            if ($self->get_metadata->is_multiple_artists) {
                if ($title =~ m{/}) {
                    ($artist, $title) = split (/\s+[\/-]\s+/, $title);
                } elsif ($title =~ /\(by (.*)\)/ ) {
                    $artist = $1;
                    $title =~ s/\(by (.*)\)//;
                }
            }
            
            $self->debug("setting track $_ title as $title");
            $self->get_track($_)->get_metadata->set_title($title);
            $self->debug("setting track $_ artist as $artist");
            $self->get_track($_)->get_metadata->set_artist($artist);
        }
        return;
    }

    method fetch_data_from_cddb {
        for my $service ($self->get_services) {
            $self->_get_data($service);
            last if ($self->has_metadata);
        }
    }

    method populate_tracks_from_toc {
        $self->info("Reading TOC ...");
        my $cd = Linux::CDROM->new("/dev/cdrom")
            or confess $Linux::CDROM::error;
        
        if ($cd->drive_status & CDS_TRAY_OPEN) {
            die "Please close the tray of your drive.\n";
        } elsif ($cd->drive_status & CDS_NO_DISC) {
            die "Please insert a disc.\n"
        } elsif ($cd->drive_status & CDS_DRIVE_NOT_READY) {
            die "Disc not ready.\n"
        }
            
        my ($first, $last) = $cd->toc;
        # Allow for the leadout track
        $last = $last - $first +1;
        $self->set_last_track_number($last);
        foreach ($first .. $last) {
            $self->set_track($_, Transcoder::Track->new(
                    format => 'cdda',
                    number => $_,
                );
            unless ($self->is_in_span($_)) {
                $self->get_track($_)->not_for_ripping();
            }
        }
        
        foreach ($first .. ($last - 1)) {
            my $frames = ($cd->toc_entry(($_ + 1))->addr 
                - $cd->toc_entry($_)->addr);
            $self->get_track($_)->set_length($frames);
            if ($cd->get_toc_entry($_)->is_data) {
                $self->get_track($_)->set_format('data');
            }
        }
        
        $self->get_track($last)->set_length( 
            $cd->toc_entry(CDROM_LEADOUT)->addr 
            - $cd->toc_entry($last)->addr );
        if ($cd->toc_entry($last)->is_data) {
            $self->get_track($last)->set_format('data');
        }
        
    }

}
