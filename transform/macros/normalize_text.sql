{% macro normalize_text(column_name) %}
    trim(both ' ,.' from regexp_replace(lower({{ column_name }}), '\s+', ' ', 'g'))
{% endmacro %}