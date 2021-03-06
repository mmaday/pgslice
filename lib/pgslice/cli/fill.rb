module PgSlice
  class CLI
    desc "fill TABLE", "Fill the partitions in batches"
    option :batch_size, type: :numeric, default: 10000, desc: "Batch size"
    option :swapped, type: :boolean, default: false, desc: "Use swapped table"
    option :source_table, desc: "Source table"
    option :dest_table, desc: "Destination table"
    option :start, type: :numeric, desc: "Primary key to start"
    option :where, desc: "Conditions to filter"
    option :sleep, type: :numeric, desc: "Seconds to sleep between batches"
    option :tw_site, type: :boolean, default: false, desc: "Force swap site_id with tw_site_id"
    def fill(table)
      table = create_table(table)
      source_table = create_table(options[:source_table]) if options[:source_table]
      dest_table = create_table(options[:dest_table]) if options[:dest_table]

      if options[:swapped]
        source_table ||= table.retired_table
        dest_table ||= table
      else
        source_table ||= table
        dest_table ||= table.intermediate_table
      end

      assert_table(source_table)
      assert_table(dest_table)

      period, field, cast, _, declarative, version, tw_site = dest_table.fetch_settings(table.trigger_name)
      tw_site ||= options[:tw_site]

      if period
        name_format = self.name_format(period)

        partitions = dest_table.partitions
        if partitions.any?
          starting_time = partition_date(partitions.first, name_format)
          ending_time = advance_date(partition_date(partitions.last, name_format), period, 1)
        end
      end

      schema_table = period && declarative ? partitions.last : table

      primary_key = schema_table.primary_key[0]
      abort "No primary key" unless primary_key

      max_source_id = nil
      begin
        max_source_id = source_table.max_id(primary_key)
      rescue PG::UndefinedFunction
        abort "Only numeric primary keys are supported"
      end

      max_dest_id =
        if options[:start]
          options[:start]
        elsif options[:swapped]
          dest_table.max_id(primary_key, where: options[:where], below: max_source_id)
        else
          dest_table.max_id(primary_key, where: options[:where])
        end

      if max_dest_id == 0 && !options[:swapped]
        min_source_id = source_table.min_id(primary_key, field, cast, starting_time, options[:where])
        max_dest_id = min_source_id - 1 if min_source_id
      end

      starting_id = max_dest_id
      fields = source_table.columns.map { |c| quote_ident(c) }.join(", ")
      fields = fields.sub(/"site_id\"/i, "\"tw_site_id\"") if tw_site
      
      batch_size = options[:batch_size]

      i = 1
      batch_count = ((max_source_id - starting_id) / batch_size.to_f).ceil

      if batch_count == 0
        log_sql "/* nothing to fill */"
      end

      tw_site_join = tw_site ? "LEFT JOIN sites_to_tag_wrap_sites sttws ON #{quote_table(source_table)}.site_id = sttws.site_id" : ""
      source_fields = tw_site ? fields.sub(/"created_time"/i, "#{quote_table(source_table)}.created_time") : fields

      while starting_id < max_source_id
        where = "#{quote_ident(primary_key)} > #{starting_id} AND #{quote_ident(primary_key)} <= #{starting_id + batch_size}"
        if starting_time
          where << " AND #{quote_ident(field)} >= #{sql_date(starting_time, cast)} AND #{quote_ident(field)} < #{sql_date(ending_time, cast)}"
        end
        if options[:where]
          where << " AND #{options[:where]}"
        end

        query = <<-SQL
/* #{i} of #{batch_count} */
INSERT INTO #{quote_table(dest_table)} (#{fields})
    SELECT #{source_fields} FROM #{quote_table(source_table)} #{tw_site_join}
    WHERE #{where}
        SQL

        run_query(query)

        starting_id += batch_size
        i += 1

        if options[:sleep] && starting_id <= max_source_id
          sleep(options[:sleep])
        end
      end
    end
  end
end
