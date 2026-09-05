package LANraragi::Plugin::Metadata::nHentaiCN;

use strict;
use warnings;
use utf8;
use feature 'state';

# nHentai CN — nHentai scraper with built-in Chinese tag translation.
# Based on LANraragi's Metadata::nHentai by Difegue and others;
# translations come from the EhTagTranslation project (db.text.json).

use URI::Escape;
use Mojo::JSON qw(decode_json);
use Mojo::UserAgent;
use File::Basename;

#You can also use the LRR Internal API when fitting.
use LANraragi::Model::Plugins;
use LANraragi::Utils::Logging qw(get_plugin_logger);
use LANraragi::Utils::Redis qw(redis_decode);

#Meta-information about your plugin.
sub plugin_info {

    return (
        #Standard metadata
        name        => "nHentai_CN",
        type        => "metadata",
        namespace   => "nhcnplugin",
        login_from  => "nhapiauth",
        author      => "Difegue and others (CN variant)",
        version     => "1.1",
        description => "Searches nHentai for tags matching your archive, and translates them to Chinese
          using an EhTagTranslation database.<br>Supports reading the ID from files formatted as \"{Id} Title\" and if not, tries to search for a matching gallery.
          <br><i class='fa fa-exclamation-circle'></i> This plugin will use the source: tag of the archive if it exists.
          <br>在 nHentai 上搜索与档案匹配的标签，并使用 EhTagTranslation 数据库将标签翻译为中文。
          <br>支持从「{Id} 标题」格式的文件名读取画廊 ID，否则尝试按标题搜索匹配的画廊。
          <br><i class='fa fa-exclamation-circle'></i> 若档案已有 source: 标签，则直接使用该画廊。",
        icon =>
          "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAIAAAAC64paAAAACXBIWXMAAAsTAAALEwEAmpwYAAAA\nB3RJTUUH4wYCFA8s1yKFJwAAAB1pVFh0Q29tbWVudAAAAAAAQ3JlYXRlZCB3aXRoIEdJTVBkLmUH\nAAACL0lEQVQ4y6XTz0tUURQH8O+59773nLFcaGWTk4UUVCBFiJs27VxEQRH0AyRo4x8Q/Qtt2rhr\nU6soaCG0KYKSwIhMa9Ah+yEhZM/5oZMG88N59717T4sxM8eZCM/ycD6Xwznn0pWhG34mh/+PA8mk\n8jO5heziP0sFYwfgMDFQJg4IUjmquSFGG+OIlb1G9li5kykgTgvzSoUCaIYlo8/Igcjpj5wOkARp\n8AupP0uzJLijCY4zzoXOxdBLshAgABr8VOp7bpAXDEI7IBrhdksnjNr3WzI4LaIRV9fk2iAaYV/y\nA1dPiYjBAALgpQxnhV2XzTCAGWGeq7ACBvCdzKQyTH+voAm2hGlpcmQt2Bc2K+ymAhWPxTzPDQLt\nOKo1FiNBQaArq9WNRQwEgKl7XQ1duzSRSn/88vX0qf7DPQddx1nI5UfHxt+m0sLYPiP3shRAG8MD\nok1XEEXR/EI2ly94nrNYWG6Nx0/2Hp2b94dv34mlZge1e4hVCJ4jc6tl9ZP803n3/i4lpdyzq2N0\n7M3DkSeF5ZVYS8v1qxcGz5+5eey4nPDbmGdE9FpGeWErVNe2tTabX3r0+Nk3PwOgXFkdfz99+exA\nMtFZITEt9F23mpLG0hYTVQCKpfKPlZ/rqWKpYoAPcTmpginW76QBbb0OBaBaDdjaDbNlJmQE3/d0\nMYoaybU9126oPkrEhpr+U2wjtoVVGBowkslEsVSupRKdu0Mduq7q7kqExjSS3V2dvwDLavx0eczM\neAAAAABJRU5ErkJggg==",
        parameters => [
            { type => "bool",   desc => "Fetch date uploaded and set timestamp tag / 抓取上传日期并写入 timestamp 标签" },
            { type => "bool",   desc => "Use the Japanese title as archive title when available (falls back to the romanised title) / 有日文标题时使用日文标题（无则回退罗马字标题）" },
            { type => "string", desc => "EhTagTranslation JSON database (db.text.json) absolute path — leave empty to skip translation / EhTagTranslation 数据库文件(db.text.json)的绝对路径，留空则不翻译" },
        ],
        oneshot_arg => "nHentai Gallery URL (Will attach tags matching this exact gallery to your archive) / nHentai 画廊 URL（将该画廊的标签精确附加到档案）"
    );

}

#Mandatory function to be implemented by your plugin
sub get_tags {

    shift;
    my $lrr_info = shift;                      # Global info hash
    my $ua       = $lrr_info->{user_agent};    # UserAgent from login plugin
    my ( $add_uploaded, $use_jpntitle, $db_path ) = @_;    # Parameters

    my $logger = get_plugin_logger();

    my $galleryID = "";

    # Quick regex to get the nh gallery id from the provided url or source tag.
    if ( $lrr_info->{oneshot_param} =~ /.*\/g\/([0-9]+).*/ ) {
        $galleryID = $1;
        $logger->debug("Skipping search and using gallery $galleryID from oneshot args");
    } elsif ( $lrr_info->{existing_tags} =~ /.*source:\s*(?:https?:\/\/)?nhentai\.net\/g\/([0-9]*).*/gi ) {

        # Matching URL Scheme like 'https://' is only for backward compatible purpose.
        $galleryID = $1;
        $logger->debug("Skipping search and using gallery $galleryID from source tag");
    } else {
        $logger->debug("Searching gallery by title (filename)");

        # lrr_info's file_path is taken straight from the filesystem, which might not be proper UTF-8.
        my $file_path = redis_decode( $lrr_info->{file_path} );

        #Get Gallery ID by hand if the user didn't specify a URL
        $galleryID = get_gallery_id_from_title( $file_path, $ua );
    }

    # Did we detect a nHentai gallery?
    if ( !$galleryID ) {
        my $message = "No matching nHentai Gallery Found!";
        $logger->info($message);
        die "${message}\n";
    }

    $logger->debug("Detected nHentai gallery ID is $galleryID");

    my %hashdata = get_tags_from_nh( $galleryID, $ua, $add_uploaded, $use_jpntitle, $db_path );

    $logger->info( "Sending the following tags to LRR: " . $hashdata{tags} );

    #Return a hash containing the new metadata - it will be integrated in LRR.
    return %hashdata;
}

######
## NH Specific Methods
######

#Uses the website's search to find a gallery and returns its content.
sub get_search_json {

    my ( $title, $ua ) = @_;

    my $logger = get_plugin_logger();

    my $URL = "https://nhentai.net/api/v2/search?query=" . uri_escape_utf8($title);

    my $res = $ua->get($URL)->result;

    if ( $res->is_error ) {
        my $code = $res->code;
        die "Search gallery by title failed! (Code: $code)\n";
    }

    $logger->debug("Tentative JSON: " . $res->body);

    return decode_json $res->body;
}

sub get_gallery_id_from_title {

    my ( $file, $ua ) = @_;
    my ( $title, $filepath, $suffix ) = fileparse( $file, qr/\.[^.]*/ );

    my $logger = get_plugin_logger();

    if ( $title =~ /\{(\d*)\}.*$/gm ) {
        $logger->debug("Got $1 from file.");
        return $1;
    }

    my $json = get_search_json( $title, $ua );

    my @results = @{ $json->{"result"} };

    if ( scalar @results > 0 ) {
        return $results[0]->{"id"};
    }

    return;
}

# retrieves the gallery JSON from NH
sub get_json_from_nh {

    my ( $gID, $ua ) = @_;

    my $logger = get_plugin_logger();

    my $URL = "https://nhentai.net/api/v2/galleries/$gID";

    my $res = $ua->get($URL)->result;

    if ( $res->is_error ) {
        my $code = $res->code;
        die "Error retrieving gallery from nHentai! (Code: $code)\n";
    }

    $logger->debug("Tentative JSON: " . $res->body);

    return decode_json $res->body;
}

sub get_tags_from_json {

    my ($json) = @_;

    my @json_tags = @{ $json->{"tags"} };
    my @tags      = ();

    foreach my $tag (@json_tags) {

        my $namespace = $tag->{"type"};
        my $name      = $tag->{"name"};

        if ( $namespace eq "tag" ) {
            push( @tags, $name );
        } else {
            push( @tags, "$namespace:$name" );
        }
    }

    return @tags;
}

sub get_title_from_json {
    my ( $json, $use_jpntitle ) = @_;
    return $json->{"title"}{"japanese"}
      if $use_jpntitle && $json->{"title"}{"japanese"};
    return $json->{"title"}{"pretty"};
}

sub get_upload_from_json {
    my ($json) = @_;
    return $json->{"upload_date"};
}

######
## EhTagTranslation lookup
######

# Loads db.text.json once per worker (state-cached).
# Returns a hashref { front => {ns => chinese_name}, data => {ns => {tag => entry}} } or {} on failure.
sub load_translation_db {
    my ($db_path) = @_;

    my $logger = get_plugin_logger();
    state $db         = {};
    state $loaded_for = "";

    return $db if %$db && $loaded_for eq $db_path;

    my $json_text = do {
        open( my $json_fh, "<", $db_path )
          or do { $logger->warn("Can't open $db_path: $!"); return {}; };
        local $/;
        <$json_fh>;
    };

    my $json = eval { decode_json($json_text) };
    unless ($json) {
        $logger->warn("Failed to parse $db_path: $@");
        return {};
    }

    my ( %front, %data );
    foreach my $element ( @{ $json->{'data'} } ) {
        my $ns = $element->{'namespace'};
        $front{$ns} = $element->{'frontMatters'}->{'name'};
        $data{$ns}  = $element->{'data'};
    }

    $db         = { front => \%front, data => \%data };
    $loaded_for = $db_path;
    return $db;
}

# Translates a list of english tags (namespaced or bare) to Chinese, EhTagConverter-style.
sub translate_tags {
    my ( $db, @tags ) = @_;

    # 裸标签（无命名空间）查表优先级；female/male 同名条目译名一致，顺序不影响译文
    my @bare_priority = qw(female male mixed other language parody character artist group cosplayer location);

    my @out;
    foreach my $item (@tags) {
        $item =~ s/^\s+|\s+$//g;
        my $new = $item;

        if ( $item =~ /^([^:]+):(.+)$/ ) {

            # 带命名空间：精确替换命名空间与词
            # db 词条为对象（含 name 等字段），译文取 ->{'name'}
            my ( $ns, $word ) = ( $1, $2 );
            $ns = 'reclass' if $ns eq 'category';    # nhentai 写 category，EhTagTranslation 叫 reclass
            if ( exists $db->{data}{$ns} ) {
                my $entry = $db->{data}{$ns}{$word};
                my $t = ( ref $entry eq 'HASH' && defined $entry->{'name'} ) ? $entry->{'name'} : $word;
                $new = "$db->{front}{$ns}:$t";
            }
        }
        elsif ($item) {

            # 裸标签：仅翻译词本身，不推断命名空间（nhentai 已丢失性别归属信息）
            foreach my $ns (@bare_priority) {
                my $entry = $db->{data}{$ns}{$item};
                next unless ref $entry eq 'HASH' && defined $entry->{'name'};
                $new = $entry->{'name'};
                last;
            }
        }
        push @out, $new;
    }
    return @out;
}

sub get_tags_from_nh {

    my ( $gID, $ua, $add_uploaded, $use_jpntitle, $db_path ) = @_;

    my %hashdata = ( tags => "" );

    my $json = get_json_from_nh( $gID, $ua );

    if ($json) {
        my @tags = get_tags_from_json($json);
        if ($add_uploaded) {
            my @upload = get_upload_from_json($json);
            push( @tags, "timestamp:@upload");
        }
        push( @tags, "source:nhentai.net/g/$gID" ) if ( @tags > 0 );

        @tags = translate_tags( load_translation_db($db_path), @tags ) if $db_path;

        # Use NH's "pretty" names unless the Japanese title was requested and exists
        $hashdata{tags}  = join( ', ', @tags );
        $hashdata{title} = get_title_from_json( $json, $use_jpntitle );
    }

    return %hashdata;
}

1;
