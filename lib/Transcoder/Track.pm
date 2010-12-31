use MooseX::Declare;

class Transcoder::Track {

    use MooseX::FollowPBP;
    use POSIX qw(mkfifo); 
    use File::Temp qw/ tempdir /; 
    use File::Copy; 
    use File::Path; 
    use Term::ProgressBar; 
    use File::Spec::Functions;
    use Unix::PID;
    use Moose::Util::TypeConstraints;

    has 'metadata' => (
        isa => 'Transcoder::MetaData';
        is => 'rw',
        lazy_build => 1,
    }

    has 'length' => (
        isa => duck_type([qw/as_lba as_msf/]),
        is => 'rw',
        handles => {
            get_frame_count => 'as_lba',
            get_min_sec_frame => 'as_msf',
        },
    );

    has format => (
        isa => enum([qw/cdda data/]),
        is => 'rw',
    );

    has audio => (
        isa => 'Bool',
        is => 'rw',
        default => 1,
        traits => [qw/Bool/],
        reader => 'is_audio',
        writer => 'set_audio',
        handles => {
            is_data => 'not',
        },
    );


    has 'to_be_ripped' => (
        isa => 'Bool',
        is => 'rw',
        default => 1,
        traits => [qw/Bool/],
        handles => {
            set_to_rip => 'set',
            not_for_ripping => 'unset',
        },
    );

    after set_format(Str $format) {
        if ($format eq 'data') {
            $self->not_for_ripping();
            $self->set_audio(1);
        } else {
            $self->set_audio(0);
        }
    }

    method _build_info {
        return Transcoder::MetaData->new_track_info;
    }
    sub encode {

        my ($self, $current, $total) = @_;
        return $current unless $self->is_audio;
        # Don't clobber existing files unnecessarily, so ask for permission if we have to.
        my $overwrite;
        if ( (-e $self->outname) and ($self->interaction) and (! $self->force) ) {
            print "Destination file already exists. Overwrite [y|N] :";
            chomp ( $overwrite = <STDIN> );
        }

        # Check it's ok to proceed, either because the file doesn't exist
        # or we can force it
        # or we have permission to overwrite this one file.
        if ( (! -e $self->outname) or ($self->force) or ($overwrite and $overwrite =~ m/(Y|y)([Ee][Ss])?/) ) {
            my $bitrate = $self->bitrate;
            my $estsize = ($bitrate * 128 * ($self->lengthLBA / 70)); # 1 kilobit = 128 bytes
            my $tempdir = tempdir(CLEANUP => 1);
            my $wavpipe = catfile ($tempdir, time.".wav");
            my $tempaac = catfile ($tempdir, time.".aac");
            my $tempm4a = catfile ($tempdir, time.".m4a");
            my $log = '/dev/null';
            if ($self->format eq 'm4a') {
                if ($self->info->bitrate <= 6400) {
                    print "File $current of $total: file is already an he-aac - copying to destination\n";
                    if ($self->{"do_not_add_cover"}) { #FIX ME!
                        copy($self->file, $self->outname);
                        return ++$current;
                    } else {
                        warn "Not doing this now - need to sort out muxing.\n";
                        return ++$current;
                        $tempaac = $self->file;
                    }
                }
            }

            # set the encoder to be either aacplusenc or faac
            my $encoder_command;
            if ($bitrate > 60) {
                $encoder_command = qq(faac -b $bitrate -o $tempaac -);
            } else {
                $encoder_command = qq(aacplusenc - $tempaac $bitrate);
            }

            unless ($tempaac eq $self->file) {
                mkfifo($wavpipe, 0777) or warn "can't mkfifo $wavpipe: $!\n" and return; # Make the pipe for the pcm data
                printf(STDERR ('-' x 20)."\nencoding %s:\n", $self->file) if ($self->verbosity > 1);
                my $encoder ="mplayer -ao pcm:fast:file=$wavpipe \"".$self->file."\" >>$log 2>&1" # to decode
                ." & sox $wavpipe -t wavpcm -c 2 - 2>$log" # for filtering
                ." | $encoder_command 2>&1 |"; # the actual encoder
                my $encoder_pid = open ENCODER, $encoder or (warn "Cannot open encoder.\n" and return);
                say $encoder."\npid = $encoder_pid" if $self->verbosity > 2;
                say "Estimated size = $estsize bytes (".($self->lengthLBA / 70).' secs)' if ($self->verbosity > 1);

                # Declare the variables needed for progress
                my ($progress, $next_update, $current_size);
                my ($old_size, $time_of_last_update) = ( 0, time);

                unless ($self->verbosity > 1) {
                    $progress = Term::ProgressBar->new({name => sprintf("Encoding %".length($total)."d of %s", 
                                $current, $total), 
                            count => $estsize, 
                            ETA   => "linear",});
                    $progress->minor(0);
                    $next_update = 0;
                }
                my $pid = Unix::PID->new();

                while ($pid->is_pid_running($encoder_pid)) {
                    $current_size = (-s $tempaac) // 0;
                    # Print a bar, or a counter, depending on the level of verbosity
                    if ($self->verbosity > 1) {
                        printf "\rCurrent size   = %".length($estsize)."d bytes", $current_size;
                    } else {
                        $next_update = $progress->update($current_size) if ($current_size >= $next_update);
                    }
                    unless ($old_size == $current_size) {
                        $time_of_last_update = time;
                        $old_size = $current_size;
                    }
                    if ( (time - $time_of_last_update) > 10) { # timeout after ten-seconds if the updating has stopped
                        close ENCODER; 
                        unlink $wavpipe;
                        return $current;
                    }
                }
                close ENCODER;
                unlink $wavpipe;
                $progress->update($estsize) unless ($self->verbosity > 1); # let's end nice and neat on 100
                printf "\rFinal size     = %".length($estsize)."d bytes (%d kbps)", 
                $current_size, 
                (($current_size / ($self->lengthLBA / 70)) / 128)
                if ($self->verbosity > 1);
                print "\n";
            }
            my $mux = sprintf (
                "MP4Box -new -add \"%s\" -itags name=\"%s\":album_artist=\"%s\":artist=\"%s\"".
                ":album=\"%s\"%s%s:genre=\"%s\":created=\"%s\":cover=\"%s\" \"%s\" >> %s 2>&1",
                $tempaac, $self->title, $self->album_artist, $self->artist, $self->album, 
                $self->number ? (sprintf ":track=\"%s\"", $self->number) : '', 
                $self->number ? (sprintf ":tracknum=\"%s%s\"", $self->number, ($self->totaltracks ? "/".$self->totaltracks : '')) : '',
                $self->genre, $self->date, $self->info->cover->tagsize, $tempm4a, $self->logfile);
            unless (-e $self->outdir) {mkpath( $self->outdir ) or die "Can't make destination directory\n";}
            my $err = system ("$mux"); # Mux the aac file into a container
            if ($err || ! -f $tempm4a) {
                warn "[ERROR] Muxing failed!\n" if ($self->verbosity > 1);
                $self->list->failure($self->file);
            } else {
                copy ($tempm4a, $self->outname);
                $self->list->success($self->outname) if (-f $self->outname);
            }
            if ($self->verbosity > 2) {
                say "$mux" ;
                say "temp aac exists" if (-f $tempaac);
                say "cover file exists" if (-f $self->cover->tagsize);
            }
            copy($self->cover->fullsize, $self->outart) if ( ($self->cover->fullsize) and not (-f $self->outart) );
        } else {
            printf "Skipping %".length($total)."d of %s: %s. - destination file already exists\n(see %s --auto and --force for more options)\n", $current, $total, $self->file, basename($0);
        }
        return ++$current;
    }
    sub minsec {
        my $self = shift;
        sprintf "%i:%02i min", @{$self->lengthMSF};
    }

}
