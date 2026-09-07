# frozen_string_literal: true

# Client for the CRS parity oracle: a live, license-free YottaDB RPMS twin
# carrying the BGP v25.1 Build 98 routine set and FileMan globals (#99 P2).
#
# Configuration is by environment — the harness never hardcodes a machine:
#
#   ROOK_CRS_TWIN_CMD   command prefix that reaches a shell inside the twin,
#                       e.g. "docker exec <container>". Unset = no twin: the
#                       CRS driver reports pending-environment and the smoke
#                       tests skip.
#   ROOK_CRS_TWIN_GLD   global directory inside the twin
#                       (default /data/g/rpms.gld)
#   ROOK_CRS_TWIN_R     routine source directory (default /data/r)
#
# The client runs M under a UTF-8 YottaDB environment with a writable
# object directory so routines auto-compile on first link. Today it offers
# probe-level execution (single expressions through direct mode) — enough
# for environment verification. FileMan seeding and CRS report invocation
# build on top of this and are NOT implemented yet; nothing here fakes them.
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
      @command_prefix = command_prefix
      @gld = gld
      @routines = routines
    end

    # Evaluates one M expression via `W <expression>` in direct mode and
    # returns the printed output (stripped of direct-mode prompts).
    def probe(expression)
      run_direct("W #{expression},!")
    end

    # Runs direct-mode M input and returns cleaned output lines. Direct mode
    # is probe-grade only: multi-line program logic belongs in a routine
    # uploaded to the twin (future seeding layer), not in fragile stdin.
    def run_direct(m_input)
      script = <<~SH
        D=$(dirname $(readlink -f /usr/local/bin/yottadb))
        mkdir -p /tmp/rook-parity-o
        export ydb_chset=UTF-8 ydb_gbldir=#{@gld}
        export ydb_routines="/tmp/rook-parity-o(#{@routines}) $D/utf8/libyottadbutil.so"
        printf '%s\\nHALT\\n' #{shell_quote(m_input)} | yottadb -dir 2>&1
      SH
      output = IO.popen([ *@command_prefix.split, "sh", "-lc", script ], &:read)
      raise Unavailable, "twin command failed: #{@command_prefix}" unless Process.last_status&.success?

      output.lines.map(&:chomp).reject { |l| l.empty? || l.start_with?("YDB>") }
    end

    private

    def shell_quote(text)
      "'#{text.gsub("'", %q('\\'')) }'"
    end
  end
end
