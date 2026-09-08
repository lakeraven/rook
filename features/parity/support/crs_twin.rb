# frozen_string_literal: true

require "shellwords"
require "English"

# Client for the CRS parity oracle: a live, license-free YottaDB RPMS twin
# carrying the BGP v25.1 Build 98 routine set and FileMan globals (#99 P2).
#
# Configuration is by environment — the harness never hardcodes a machine:
#
#   ROOK_CRS_TWIN_CMD   command prefix that reaches a shell inside the twin,
#                       e.g. "docker exec <container>". Unset = no twin: the
#                       CRS driver reports pending-environment and the smoke
#                       tests skip. Split with shell-word rules.
#   ROOK_CRS_TWIN_GLD   global directory inside the twin
#                       (default /data/g/rpms.gld)
#   ROOK_CRS_TWIN_R     routine source directory (default /data/r)
#
# The client runs M under a UTF-8 YottaDB environment with a writable object
# directory so routines auto-compile on first link. It offers probe-grade
# direct-mode evaluation plus routine installation (for the FileMan seeding
# layer, which needs real programs, not stdin fragments). An M error in the
# output raises — a failed evaluation must never read as a successful probe.
module ParityHarness
  class CrsTwin
    class Unavailable < StandardError; end

    def self.configured?
      !ENV["ROOK_CRS_TWIN_CMD"].to_s.strip.empty?
    end

    def self.from_env
      raise Unavailable, "set ROOK_CRS_TWIN_CMD to reach a twin" unless configured?

      new(ENV.fetch("ROOK_CRS_TWIN_CMD"),
        gld: ENV.fetch("ROOK_CRS_TWIN_GLD", "/data/g/rpms.gld"),
        routines: ENV.fetch("ROOK_CRS_TWIN_R", "/data/r"))
    end

    def initialize(command_prefix, gld:, routines:)
      @command_prefix = Shellwords.split(command_prefix)
      @gld = gld
      @routines = routines
    end

    # Evaluates one M expression via `W <expression>` in direct mode and
    # returns the printed output lines.
    def probe(expression)
      run_direct("W #{expression},!")
    end

    # Runs direct-mode M input and returns cleaned output lines, raising on
    # any %YDB-E / %SYSTEM-E error the twin printed.
    def run_direct(m_input, allow_errors: false)
      script = <<~SH
        set -eu
        D=$(dirname $(readlink -f /usr/local/bin/yottadb))
        mkdir -p /tmp/rook-parity /tmp/rook-parity-o
        export ydb_chset=UTF-8 ydb_gbldir=#{Shellwords.escape(@gld)}
        export ydb_routines="/tmp/rook-parity-o(/tmp/rook-parity #{Shellwords.escape(@routines)}) $D/utf8/libyottadbutil.so"
        printf '%s\\nHALT\\n' #{Shellwords.escape(m_input)} | yottadb -dir 2>&1
      SH
      lines = run_shell(script).lines.map(&:chomp).reject { |l| l.empty? || l.start_with?("YDB>") }
      if !allow_errors && (error = lines.find { |l| l.start_with?("%YDB-E", "%SYSTEM-E") })
        raise Unavailable, "twin M error: #{error}"
      end
      lines
    end

    # Installs an M routine source into the twin's harness routine directory
    # (base64 through the shell — no stdin dependence on the exec prefix).
    # Stale objects are removed so the next link recompiles.
    def install_routine(name, source)
      raise ArgumentError, "invalid M routine name #{name.inspect}" unless name.match?(/\A[A-Z][A-Z0-9]{0,7}\z/)

      encoded = [ source ].pack("m0")
      run_shell(<<~SH)
        set -eu
        mkdir -p /tmp/rook-parity /tmp/rook-parity-o
        printf '%s' #{Shellwords.escape(encoded)} | base64 -d > /tmp/rook-parity/#{name}.m
        rm -f /tmp/rook-parity-o/#{name}.o
      SH
      name
    end

    # Runs `D <entry>` (e.g. "^ROOKSEED" or "PT^ROOKSEED(...)") — installed
    # routines resolve from the harness routine directory.
    def run_entry(entry, allow_errors: false)
      run_direct("D #{entry}", allow_errors: allow_errors)
    end

    private

    def run_shell(script)
      output = IO.popen([ *@command_prefix, "sh", "-c", script ], &:read)
      raise Unavailable, "twin command failed: #{@command_prefix.join(' ')}" unless $CHILD_STATUS.success?

      output
    end
  end
end
