# encoding: UTF-8

class Triki
  struct Mysql
    alias Field = String?

    include Triki::InsertStatementParser
    include Triki::ConfigScaffoldGenerator

    def parse_insert_statement(line)
      if regex_match = insert_regex.match(line)
        {
          "ignore"       => !regex_match[1]?.nil?,
          "table_name"   => regex_match[2],
          "column_names" => regex_match[3].split(/`\s*,\s*`/).map(&.gsub('`', "")),
        }
      end
    end

    def make_insert_statement(table_name, column_names, values, ignore = nil)
      values_strings = values.map do |string_values|
        "(" + string_values.join(",") + ")"
      end.join(",")

      "INSERT #{ignore ? "IGNORE " : ""}INTO `#{table_name}` (`#{column_names.join("`, `")}`) VALUES #{values_strings};"
    end

    def insert_regex
      /^\s*INSERT\s*(IGNORE )?\s*INTO `(.*?)` \((.*?)\) VALUES\s*/i
    end

    def rows_to_be_inserted(line) : Array(Array(String?))
      line = line.gsub(insert_regex, "").gsub(/\s*;\s*$/, "")
      context_aware_mysql_string_split(line)
    end

    def make_valid_value_string(value)
      if value.nil?
        "NULL"
      elsif value =~ /^0x[0-9a-fA-F]+$/
        value
      else
        "'" + value.to_s + "'"
      end
    end

    # Be aware, strings must be quoted in single quotes!
    # ameba:disable Metrics/CyclomaticComplexity
    def context_aware_mysql_string_split(string) : Array(Array(String?))
      in_sub_insert = false
      in_quoted_string = false
      escaped = false
      current_field : String? = nil
      fields = [] of Field
      output = [] of Array(Field)

      string.each_char do |i|
        if escaped
          escaped = false
          current_field ||= ""
          current_field += i
        else
          if i == '\\'
            escaped = true
            current_field ||= ""
            current_field += i
          elsif i == '(' && !in_quoted_string && !in_sub_insert
            in_sub_insert = true
          elsif i == ')' && !in_quoted_string && in_sub_insert
            fields << current_field unless current_field.nil?
            output << fields unless fields.empty?
            in_sub_insert = false
            fields = [] of Field
            current_field = nil
          elsif i == '\'' && !in_quoted_string
            fields << current_field unless current_field.nil?
            current_field = ""
            in_quoted_string = true
          elsif i == '\'' && in_quoted_string
            fields << current_field unless current_field.nil?
            current_field = nil
            in_quoted_string = false
          elsif i == ',' && !in_quoted_string && in_sub_insert
            fields << current_field unless current_field.nil?
            current_field = nil
          elsif i == 'L' && !in_quoted_string && in_sub_insert && current_field == "NUL"
            current_field = nil
            fields += [current_field]
          elsif (i == ' ' || i == '\t') && !in_quoted_string
            # Don't add whitespace not in a string
          elsif in_sub_insert
            current_field ||= ""
            current_field += i
          end
        end
      end

      fields << current_field unless current_field.nil?
      output << fields unless fields.empty?
      output
    end
  end
end
