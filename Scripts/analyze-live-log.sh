#!/usr/bin/env bash
set -euo pipefail

LOG_PATH="${1:-$HOME/Library/Application Support/Live Loupe/live-debug.log}"

if [[ ! -f "$LOG_PATH" ]]; then
  echo "No log found at: $LOG_PATH" >&2
  exit 1
fi

echo "Log: $LOG_PATH"
echo

perl -ne '
  # Lightroom/Lua timestamps are seconds since 2001-01-01. App timestamps are
  # Unix epoch seconds. Convert plugin times so server lag is directly visible.
  if (/^\S+\s+\S+\s+([0-9.]+)\s+plugin\s+render OK .*waitForRender=([0-9.]+).*total=([0-9.]+).*longEdge=([0-9]+).*q=([0-9.]+)/) {
    push @pending_render_ok, ($1 + 978307200);
    push @wait, $2 + 0;
    push @total, $3 + 0;
    $edge{$4}++;
    $quality{$5}++;
    next;
  }

  if (/render OK .*waitForRender=([0-9.]+).*total=([0-9.]+).*longEdge=([0-9]+).*q=([0-9.]+)/) {
    push @wait, $1 + 0;
    push @total, $2 + 0;
    $edge{$3}++;
    $quality{$4}++;
  }

  if (/^([0-9.]+)\s+app\s+manifest live modified=/ && @pending_render_ok) {
    my $render_ok = shift @pending_render_ok;
    push @manifest_delay, ($1 + 0) - $render_ok;
  }

  $render_start++ if /render START/;
  $render_error++ if /render ERROR|render FAIL|loop ERROR|MOVE_FAIL|REPLACE_FAIL/;
  $rename_error++ if /attempt to call field .rename./;
  $manifest++ if /manifest live modified=/;
  $queued++ if /render queued/;
  $changes++ if /change queued|force render queued/;
  $legacy_changes++ if /force render queued/;
  $screen_errors++ if /screen ERROR/;
  if (/screen frame .*fps=([0-9.]+) capture=([0-9.]+)ms encode=([0-9.]+)ms bytes=([0-9]+)/) {
    push @screen_fps, $1 + 0;
    push @screen_capture, $2 + 0;
    push @screen_encode, $3 + 0;
    push @screen_bytes, $4 + 0;
    if (/screen frame .*mode=([a-z]+)/) {
      $screen_modes{$1}++;
    }
    if (/screen frame .*transport=([a-z]+)/) {
      $screen_transports{$1}++;
    }
    if (/screen frame .*idle=(true|false)/) {
      $screen_idle{$1}++;
    }
  }
  END {
    print "Events:\n";
    printf "  change queued: %d\n", $changes || 0;
    printf "  legacy force queued lines: %d\n", $legacy_changes || 0;
    printf "  render queued: %d\n", $queued || 0;
    printf "  render start:  %d\n", $render_start || 0;
    printf "  render ok:     %d\n", scalar(@wait);
    printf "  render errors: %d\n", $render_error || 0;
    printf "  os.rename errors: %d\n", $rename_error || 0;
    printf "  manifest live: %d\n", $manifest || 0;
    printf "  screen frames: %d\n", scalar(@screen_fps);
    printf "  screen errors: %d\n", $screen_errors || 0;

    if (@wait) {
      @s = sort { $a <=> $b } @wait;
      $n = @s;
      $sum = 0;
      $sum += $_ for @s;
      $p50 = $s[int(($n - 1) * 0.50)];
      $p90 = $s[int(($n - 1) * 0.90)];
      printf "\nwaitForRender seconds:\n";
      printf "  n=%d min=%.2f p50=%.2f avg=%.2f p90=%.2f max=%.2f\n",
        $n, $s[0], $p50, $sum / $n, $p90, $s[-1];
    }

    if (@manifest_delay) {
      @d = sort { $a <=> $b } @manifest_delay;
      $dn = @d;
      $dsum = 0;
      $dsum += $_ for @d;
      $dp50 = $d[int(($dn - 1) * 0.50)];
      $dp90 = $d[int(($dn - 1) * 0.90)];
      printf "\nrender OK -> manifest live seconds:\n";
      printf "  n=%d min=%.3f p50=%.3f avg=%.3f p90=%.3f max=%.3f\n",
        $dn, $d[0], $dp50, $dsum / $dn, $dp90, $d[-1];
    }

    if (@screen_fps) {
      @fps = sort { $a <=> $b } @screen_fps;
      @cap = sort { $a <=> $b } @screen_capture;
      @enc = sort { $a <=> $b } @screen_encode;
      $sn = @fps;
      printf "\nScreen Live samples:\n";
      printf "  fps min=%.1f p50=%.1f max=%.1f\n",
        $fps[0], $fps[int(($sn - 1) * 0.50)], $fps[-1];
      printf "  capture ms p50=%.1f max=%.1f\n",
        $cap[int(($sn - 1) * 0.50)], $cap[-1];
      printf "  encode ms p50=%.1f max=%.1f\n",
        $enc[int(($sn - 1) * 0.50)], $enc[-1];

      if (%screen_modes) {
        print "  modes:";
        for $k (sort keys %screen_modes) {
          printf " %s=%d", $k, $screen_modes{$k};
        }
        print "\n";
      }

      if (%screen_transports) {
        print "  transport:";
        for $k (sort keys %screen_transports) {
          printf " %s=%d", $k, $screen_transports{$k};
        }
        print "\n";
      }

      if (%screen_idle) {
        print "  idle:";
        for $k (sort keys %screen_idle) {
          printf " %s=%d", $k, $screen_idle{$k};
        }
        print "\n";
      }
    }

    if (%edge) {
      print "\nLive long edge values:\n";
      for $k (sort { $a <=> $b } keys %edge) {
        printf "  %s px: %d\n", $k, $edge{$k};
      }
    }

    if (%quality) {
      print "\nLive quality values:\n";
      for $k (sort { $a <=> $b } keys %quality) {
        printf "  %s: %d\n", $k, $quality{$k};
      }
    }
  }
' "$LOG_PATH"

echo
echo "Recent timing lines:"
rg 'live START|screen START|develop poll mode|live timing|change queued|force render queued|render queued|render START|render OK|render ERROR|render FAIL|loop ERROR|manifest live|screen frame|screen ERROR' "$LOG_PATH" | tail -n 80
