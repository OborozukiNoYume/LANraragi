package LANraragi::Plugin::Scripts::EhTagAutoUpdater;

use strict;
use warnings;
use utf8;

use Mojo::UserAgent;
use Mojo::File;
use Encode;

use LANraragi::Utils::Logging qw(get_plugin_logger);

# Plugin metadata
sub plugin_info {

    return (
        # Standard metadata
        name        => "EhTag Translation Auto-Updater",
        type        => "script",
        namespace   => "ehtag_auto_updater",
        author      => "Community",
        version     => "1.0",
        description =>
          "Auto-detects updates from EhTagTranslation/Database, downloads db.text.json, " .
          "applies custom text replacements, and updates the system database.<br>" .
          "自动检测 EhTagTranslation 数据库更新，下载 db.text.json 并进行文本替换。",
        icon        =>
          "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA" .
          "sTAAALEwEAmpwYAAAAB3RJTUUH4wYCFQocjU4r+QAAAB1pVFh0Q29tbWVudAAAAAAAQ3JlYXRlZCB3aXRoIEdJTVBkLmUHAAADMElEQVQ4" .
          "y42US2xUZRiGn/8/Z87czr1zpzMdSqd0Oi0UKBelo1SLUsSiRkU0JMYEl8aNbly5EhI3JuwAFoYEIxEWLDQCGhKRBAdCILFEBRKhtNpKy" .
          "0ApzGXO+c/Phc6A7YD9tk/yfn/e/N//JQLwxB2vp5quDl/EcJyhDK30RRrJqgifHgPp3VVQ+pZ/sEv0R47OHx/9+Esv+P2f0yVnnzh48P" .
          "ND0bKFjT8Yo70TBaLbNm4phtB30DSQnTZBv3BmAjy+uyWw5xGXuE/HY6bP63sJBFbce4XoBnB0pP/p7MWjfxoHq7tfhCJ+x0CXTX7eCEe" .
          "BkP0kPkdU1E+9PHrzl3f2u9IWAL+W1lxd/+u1fZO/3LVl67J14rKzFjvfvBdP8BLpk+n8XCOKgaJvS2tyPK/XCHQY+NJLzEbgBwJlhGnP" .
          "OQdD2a62LK9H0A+dMJ/bW6JckQBZXV4zXdq4paakHZ1SfPEd4CVgL/A78ATQ64tPMwmWXHe57U8MYTMgv2+8lDvP89lrt3/c7PF4u4PuX" .
          "c/5QZrj8z4hkn3IYJYmQP7mOPCocDLBV0Z4AcRVmC9amcXNjSxZU2fgz9jk5wPD9e7V6KKaE2WvnDzpxDV0rk4AMeCz2WJVqyBEBfC2CN" .
          "oCBk5FjIFWYOEm+MAbA8cNQ7vudJwDf+s8tg5aNAFiWDAAfG2z8jqY+G04twH7gVXA/mLQJXaC+oJVwBJgZQFYrAA3A0eBbtd1d4rI08B" .
          "zwDvAn0AF+FNV+4HV+Ri1fL4bAHeApQWwL4CB/Pt8fgbYD2wFNovIQ8AeIAa0i0iJqq4H1gGtqnoIeBw4DIwBzwNdBkgHRWQV0A6cGh2+" .
          "vLk+3NwTbU9bMTdwJT+3NMAyYJmqvg/sALYAb4nIFSBiwAsiciRffgDckf/+JPAtcByYB1wCuoAqYC2wT0Q2ZGOZ4tGRq38BIxgd7g+1N" .
          "q7tuD1W1XHvnKI0oIRALv+DUtU+Vb2MqlYDYeBR4AXgY+CDXE7PjVy9OmrVLfgY9TbNxFDDq9C7/f0B4J3SZbGxpuW1pwDKQ8lA+XR6ou" .
          "T/nP8N6j0YApxZq4IAAAAASUVORK5CYII=",
    );

}

# Mandatory function for script plugins
sub run_script {
    shift;
    my ( $lrr_info, $params ) = @_;

    # ============================================
    # 1. Configuration
    # ============================================
    my $api_url      = "https://api.github.com/repos/EhTagTranslation/Database/releases/latest";
    my $db_path      = "./database/db.text.json";
    my $version_path = "./database/db.version";
    my $logger       = get_plugin_logger();

    $logger->info("Starting EhTag translation database update check...");

    # ============================================
    # 2. Version Check
    # ============================================
    # Use provided UserAgent from LRR (pre-configured with login cookies if needed)
    my $ua = $lrr_info->{user_agent};
    $ua->max_redirects(5);

    # Fetch latest release info from GitHub API
    my $api_response;
    eval {
        $api_response = $ua->get($api_url)->result;
    };
    if ($@ || !$api_response || !$api_response->is_success) {
        my $err_msg = $@ || ($api_response ? $api_response->message : "Unknown error");
        $logger->error("Failed to fetch GitHub API: $err_msg");
        return ( error => "Failed to fetch GitHub API: $err_msg" );
    }

    # Parse JSON response
    my $release_info;
    eval {
        $release_info = $api_response->json;
    };
    if ($@ || !$release_info) {
        $logger->error("Failed to parse GitHub API response as JSON.");
        return ( error => "Failed to parse GitHub API response." );
    }

    # Extract remote version (tag_name)
    my $remote_version = $release_info->{tag_name};
    if (!$remote_version) {
        $logger->error("No tag_name found in GitHub API response.");
        return ( error => "No tag_name found in GitHub API response." );
    }
    $logger->info("Remote version: $remote_version");

    # Read local version
    my $local_version = "";
    my $version_file  = Mojo::File->new($version_path);
    if (-e $version_path) {
        eval {
            $local_version = $version_file->slurp;
            $local_version =~ s/^\s+|\s+$//g;  # Trim whitespace
        };
        if ($@) {
            $logger->warn("Could not read version file: $@");
        }
    }
    $logger->info("Local version: " . ($local_version || "(not found)"));

    # Check if update is needed
    my $db_file = Mojo::File->new($db_path);
    if ($remote_version eq $local_version && -e $db_path) {
        $logger->info("Database is already up to date.");
        return ( success => 1, message => "Up to date (version: $local_version)" );
    }

    # ============================================
    # 3. Download & Process
    # ============================================
    $logger->info("Update available. Downloading new database...");

    # Find db.text.json download URL from assets
    my $download_url = "";
    my $assets = $release_info->{assets} || [];
    for my $asset (@$assets) {
        if ($asset->{name} eq "db.text.json") {
            $download_url = $asset->{browser_download_url};
            last;
        }
    }

    if (!$download_url) {
        $logger->error("Could not find db.text.json in release assets.");
        return ( error => "Could not find db.text.json in release assets." );
    }
    $logger->info("Download URL: $download_url");

    # Download the database file
    my $download_response;
    eval {
        $download_response = $ua->get($download_url)->result;
    };
    if ($@ || !$download_response || !$download_response->is_success) {
        my $err_msg = $@ || ($download_response ? $download_response->message : "Unknown error");
        $logger->error("Failed to download database: $err_msg");
        return ( error => "Failed to download database: $err_msg" );
    }

    # Get content as bytes and decode as UTF-8
    my $content;
    eval {
        my $bytes = $download_response->body;
        $content = Encode::decode_utf8($bytes);
    };
    if ($@ || !defined $content) {
        $logger->error("Failed to decode database content as UTF-8: $@");
        return ( error => "Failed to decode database content as UTF-8." );
    }

    $logger->info("Download complete. Size: " . length($content) . " characters");

    # Text replacement: "重新分类" -> "类别"
    my $replacement_count = 0;
    $replacement_count = ($content =~ s/"重新分类"/"类别"/g) || 0;
    $logger->info("Text replacement complete. Replaced $replacement_count occurrences.");

    # ============================================
    # 4. File Operations
    # ============================================

    # Ensure database directory exists
    my $db_dir = Mojo::File->new("./database");
    if (!-d "./database") {
        eval {
            $db_dir->make_path;
        };
        if ($@) {
            $logger->error("Failed to create database directory: $@");
            return ( error => "Failed to create database directory: $@" );
        }
    }

    # Backup existing database file (use copy to preserve original in case of write failure)
    if (-e $db_path) {
        my $backup_path = $db_path . ".bak";
        eval {
            Mojo::File->new($db_path)->copy_to($backup_path);
        };
        if ($@) {
            $logger->warn("Failed to backup existing database: $@");
            # Continue anyway, this is not critical
        } else {
            $logger->info("Backed up existing database to $backup_path");
        }
    }

    # Write new database file (ensure UTF-8 encoding)
    eval {
        my $encoded_content = Encode::encode_utf8($content);
        Mojo::File->new($db_path)->spurt($encoded_content);
    };
    if ($@) {
        $logger->error("Failed to write database file: $@");
        return ( error => "Failed to write database file: $@" );
    }
    $logger->info("Database file written to $db_path");

    # Write version file
    eval {
        Mojo::File->new($version_path)->spurt($remote_version);
    };
    if ($@) {
        $logger->error("Failed to write version file: $@");
        return ( error => "Failed to write version file: $@" );
    }
    $logger->info("Version file updated to $remote_version");

    # ============================================
    # 5. Return Success
    # ============================================
    my $message = "Updated to $remote_version. Replaced $replacement_count terms.";
    $logger->info("Update complete: $message");

    return ( success => 1, message => $message );
}

1;
