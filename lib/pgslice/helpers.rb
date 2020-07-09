module PgSlice
  module Helpers
    SQL_FORMAT = {
      day: "YYYYMMDD",
      month: "YYYYMM",
      year: "YYYY"
    }

    protected

    # output

    def log(message = nil)
      error message
    end

    def log_sql(message = nil)
      say message
    end

    def abort(message)
      raise Thor::Error, message
    end

    # database connection

    def connection
      @connection ||= begin
        url = options[:url] || ENV["PGSLICE_URL"]
        abort "Set PGSLICE_URL or use the --url option" unless url

        uri = URI.parse(url)
        params = CGI.parse(uri.query.to_s)
        # remove schema
        @schema = Array(params.delete("schema") || "public")[0]
        uri.query = URI.encode_www_form(params)

        ENV["PGCONNECT_TIMEOUT"] ||= "1"
        PG::Connection.new(uri.to_s)
      end
    rescue PG::ConnectionBad => e
      abort e.message
    rescue URI::InvalidURIError
      abort "Invalid url"
    end

    def schema
      connection # ensure called first
      @schema
    end

    def execute(query, params = [])
      connection.exec_params(query, params).to_a
    end

    def run_queries(queries)
      connection.transaction do
        execute("SET LOCAL client_min_messages TO warning") unless options[:dry_run]
        log_sql "BEGIN;"
        log_sql
        run_queries_without_transaction(queries)
        log_sql "COMMIT;"
      end
    end

    def run_query(query)
      log_sql query
      unless options[:dry_run]
        begin
          execute(query)
        rescue PG::ServerError => e
          abort("#{e.class.name}: #{e.message}")
        end
      end
      log_sql
    end

    def run_queries_without_transaction(queries)
      queries.each do |query|
        run_query(query)
      end
    end

    def server_version_num
      execute("SHOW server_version_num")[0]["server_version_num"].to_i
    end

    # helpers

    def sql_date(time, cast, add_cast = true)
      if cast == "timestamptz"
        fmt = "%Y-%m-%d %H:%M:%S UTC"
      else
        fmt = "%Y-%m-%d"
      end
      str = "'#{time.strftime(fmt)}'"
      add_cast ? "#{str}::#{cast}" : str
    end

    def name_format(period)
      case period.to_sym
      when :day
        "%Y%m%d"
      when :month
        "%Y%m"
      else
        "%Y"
      end
    end

    def partition_date(partition, name_format)
      DateTime.strptime(partition.name.split("_").last, name_format)
    end

    def round_date(date, period)
      date = date.to_date
      case period.to_sym
      when :day
        date
      when :month
        Date.new(date.year, date.month)
      else
        Date.new(date.year)
      end
    end

    def assert_table(table)
      abort "Table not found: #{table}" unless table.exists?
    end

    def assert_no_table(table)
      abort "Table already exists: #{table}" if table.exists?
    end

    def advance_date(date, period, count = 1)
      date = date.to_date
      case period.to_sym
      when :day
        date.next_day(count)
      when :month
        date.next_month(count)
      else
        date.next_year(count)
      end
    end

    def quote_ident(value)
      PG::Connection.quote_ident(value)
    end

    def quote_table(table)
      table.quote_table
    end

    def quote_no_schema(table)
      quote_ident(table.name)
    end

    def create_table(name)
      if name.include?(".")
        schema, name = name.split(".", 2)
      else
        schema = self.schema
      end
      Table.new(schema, name)
    end

    def make_index_def(index_def, table, tw_site = false)
      new_index_def = index_def.sub(/ ON \S+ USING /, " ON #{quote_table(table)} USING ").sub(/ INDEX .+ ON /, " INDEX ON ") + ";"
      if tw_site
        new_index_def = new_index_def.gsub(/\bsite_id\b/i, "tw_site_id")
      end
      new_index_def
    end

    def make_fk_def(fk_def, table, tw_site = false)
      new_fk_def = "ALTER TABLE #{quote_table(table)} ADD #{fk_def};"
      if tw_site
        new_fk_def = new_fk_def.sub(/\bsite_id/i, "tw_site_id").sub(/\bsites\b/i, "tag_wrap_sites")
      end
      new_fk_def
    end
  end
end
