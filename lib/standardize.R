library(here)
source(here::here("lib", "utils.R"))
source(here::here("lib", "sanitizers.R"))


standardize <- function(data, metadata) {
  # NOTE: rows that were merged will likley have some values coerced to NA when
  # types are enforced. For instance, let's say a car was stopped with 2 people
  # ages 18 and 22, with a row per person for that stop. If those rows are
  # merged, the age value in that record will be 18<sep>22; when age is later
  # coerced to an integer type, this value will be coerced to NA; typically,
  # this is what you want unless you have some logic for selecting one value
  # over another; if that's the case, a new column should be created that
  # reflects that choice
  d <- list(
      data = data,
      # collect metadata local to standardize here
      metadata = list()
    ) %>%
    add_calculated_columns %>%
    select_only_schema_cols %>%
    enforce_types %>%
    correct_predicates %>%
    sanitize

  # put all local metadata in standarize sublist of all metadata
  metadata[["standardize"]] <- d$metadata
  list(
    data = d$data,
    metadata = metadata
  )
}


add_calculated_columns <- function(d) {
  print("adding calculated columns...")
  for(col in colnames(d$data)) {
    if (endsWith(col, "_dob")) {
      new_colname <- str_c(prefix(col), "_", "age")
      d$data[[new_colname]] <- age_at_date(d$data[[col]], d$data[["date"]])
    }
    if (col == "officer_id") {
      h <- function(s) if (is.na(s)) NA_character_ else substr(digest(s), 1, 10)
      d$data[["officer_id_hash"]] <- simple_map(d$data[[col]], h)
    }
  }
  d
}


select_only_schema_cols <- function(d) {
  cols = intersect(names(schema), colnames(d$data))
  d$data <- select_(d$data, .dots = cols)
  d
}


correct_predicates <- function(d) {
  print("correcting predicated columns...")
  # TODO(danj): add a function record not just change in null rates but
  # distribution of values, i.e. TRUE -> FALSE
  f <- function(predicate_v, if_not) {
    function(predicated_v) {
      if_else(as.logical(predicate_v), predicated_v, if_not)
    }
  }
  predication_schema <- c()
  for (predicated_column in names(predicated_columns)) {
    if (predicated_column %in% colnames(d$data)) {
      predicate_column <- predicated_columns[[predicated_column]]$predicate
      if_not <- predicated_columns[[predicated_column]]$if_not
      predication_schema <- append_to(
        predication_schema,
        predicated_column,
        f(d$data[[predicate_column]], if_not)
      )
    }
  }
  res <- apply_schema_and_collect_null_rates(predication_schema, d$data)
  d$data <- res$data
  d$metadata[["predication_correction"]] <- res$null_rates
  d
}


enforce_types <- function(d) {
  print("enforcing standard types...")
  res <- apply_schema_and_collect_null_rates(schema, d$data)
  d$data <- res$data
  d$metadata[["enforce_types"]] <- res$null_rates
  d
}


prefix <- function(s) {
  str_split(s, "_")[[1]][1]
}


sanitize <- function(d) {
  print("sanitizing...")
  sanitize_schema <- c()
  for (col in colnames(d$data)) {
    if (endsWith(col, "date")) {
      sanitize_schema <- append_to(sanitize_schema, col, sanitize_date)
    }
    if (endsWith(col, "age")) {
      sanitize_schema <- append_to(sanitize_schema, col, sanitize_age)
    }
    if (endsWith(col, "dob")) {
      sanitize_schema <- append_to(
        sanitize_schema,
        col,
        sanitize_dob_func(d$data$date)
      )
    }
    if (col == "vehicle_year") {
      sanitize_schema <- append_to(
        sanitize_schema,
        col,
        sanitize_vehicle_year_func(d$data$date)
      )
    }
  }
  x <- apply_schema_and_collect_null_rates(sanitize_schema, d$data)
  d$data <- x$data
  d$metadata[["sanitize"]] <- x$null_rates
  d
}
