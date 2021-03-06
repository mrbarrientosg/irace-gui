createHiddenDirectory <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path)
    if (.Platform$OS.type == "windows") {
      # Invisible directory in windows
      system2(command = "attrib", args = paste("+h", path))
    }
  }
}

get_option <- function(name, default = NULL) {
  if (is.null(get_golem_options(name)))
    return(default)

  return(get_golem_options(name))
}

parameters_as_irace <- function(parameters) {
  params <- capture.output(
            write.table(
              parameters,
              row.names = FALSE,
              col.names = FALSE,
              sep = "\t",
              quote = F
            )
          )
  params <- paste0(params, collapse = "\n")

  irace::readParameters(text = params)
}

alert.error <- function(message = NULL) {
  shinyalert(
    title = "Error",
    text = message,
    type = "error",
    closeOnClickOutside = TRUE
  )
}

write.list <- function(x, file, export) {
  x[sapply(x, is.null)] <- NULL
  x[sapply(x, is.na)] <- NULL
  x[sapply(x, is.empty)] <- NULL
  names(x)[names(x) == "onlyTest"] <- ".onlytest"

  lines <- lapply(names(x), function(name) {
    paste(name, "=", if (is.logical(x[[name]])) as.integer(x[[name]]) else x[[name]])
  })

  data <- ""

  if (export) {
    data <- "# The value of these parameter must be set manually"
    data <- c(
      data,
      'parameterFile = ""',
      'trainInstancesFile = ""',
      'trainInstancesDir = ""',
      'scenarioFile = ""',
      'execDir = ""',
      'logFile = ""',
      'configurationsFile = ""',
      'forbiddenFile = ""',
      'testInstancesFile = ""',
      'testInstancesDir = ""'
    )
  }

  data <- c(data, "\n", lines)

  write(x = paste0(data), sep = "\n", file = file)
}

checkNull <- function(x, default) {
  if (is.null(x))
    default
  else
    x
}

save_plot_as_base64 <- function(width = 550, height = 550) {
  filePlot <- tempfile(fileext = ".png")
  plot <- recordPlot()
  png(filePlot, width = width, height = height)
  plot.new()
  print(plot)
  dev.off()
  on.exit(file.remove(filePlot))
  return(knitr::image_uri(filePlot))
}


create_scenario_file <- function(path, pg, name = "scenario.txt", export = FALSE) {
  if (!is.null(name) && name != "") {
    path <- file.path(path, name)
  }

  if (export) {
    pg$clear_scenario_temp()
  }

  write.list(pg$get_irace_options(), file = path, export)
}

create_parameter_file <- function(path, pg, name = "parameters.txt") {
  if (!is.null(name) && name != "") {
    path <- file.path(path, name)
  }
  parameters <- data.table(pg$get_parameters())
  write.table(parameters, path, row.names = FALSE, col.names = FALSE, sep = "\t", quote = F)
}

create_instances_file <- function(path, pg, name = "instances.txt") {
  if (!is.null(name) && name != "") {
    path <- file.path(path, name)
  }

  write(paste(pg$get_train_instances(), collapse = "\n"), file = path)
}

create_target_runner_file <- function(path, pg, name = "target-runner") {
  if (!is.null(name) && name != "") {
    path <- file.path(path, name)

    if (.Platform$OS.type == "windows") {
      path <- paste0(path, ".bat")
    }
  }

  write(paste(pg$get_target_runner(), collapse = "\n"), file = path)

  if (.Platform$OS.type == "unix") {
    Sys.chmod(path, mode = "0771")
  }
}

create_target_evaluator_file <- function(path, pg, name = "target-evaluator") {
  if (!is.null(name) && name != "") {
    path <- file.path(path, name)

    if (.Platform$OS.type == "windows") {
      path <- paste0(path, ".bat")
    }
  }

  write(paste(pg$get_target_evaluator(), collapse = "\n"), file = path)

  if (.Platform$OS.type == "unix") {
    Sys.chmod(path, mode = "0771")
  }
}

create_initial_config_file <- function(path, pg, name = "configurations.txt") {
  if (!is.null(name) && name != "") {
    path <- file.path(path, name)
  }

  if (nrow(pg$get_configurations()) > 0) {
    configurations <- data.table(pg$get_configurations(), stringsAsFactors = FALSE)
    write.table(configurations, path, row.names = FALSE, col.names = TRUE, sep = "\t")
  } else {
    cat("", file = path)
  }
}

create_forbidden_file <- function(path, pg, name = "forbidden.txt") {
  if (!is.null(name) && name != "") {
    path <- file.path(path, name)
  }
  write(paste(pg$get_forbidden(), collapse = "\n"), file = path)
}

create_test_instances_file <- function(path, pg, name = "test-instances.txt") {
  if (!is.null(name) && name != "") {
    path <- file.path(path, name)
  }
  write(paste(pg$get_test_instances(), collapse = "\n"), file = path)
}

extract.parameters <- function(parameters) {
  log_info("Extracting paremeters from irace format to data frame")
  types <- c()
  switches <- c()
  domain <- c()
  conditions <- c()
  for (name in parameters$names) {
    types <- c(types, parameters$type[[name]])
    switches <- c(switches, paste0("\"", parameters$switches[[name]], "\""))
    domain <- c(domain, paste0("(", paste(parameters$domain[[name]], collapse = ", "), ")"))
    if (is.expression(parameters$conditions[[name]])) {
      conditions <- c(conditions, paste("|", parameters$conditions[[name]], collapse = ", "))
    } else {
      conditions <- c(conditions, "")
    }
  }

  df <- data.frame(list(names = parameters$names, switches = switches, types = types, domain = domain, conditions = conditions), stringsAsFactors = FALSE)

  return(df)
}

convert_vector_to_string <- function(vector) {
  newVector <- c()
  for (i in 1:length(vector)) {
    newVector[i] <- paste0(vector[i])
  }
  return(newVector)
}

checkPath <- function(path) {
  return(!is.null(path) && fs::is_absolute_path(path) && file.exists(path))
}

importScenario <- function(name, path, scenario, onlyOptions = FALSE) {
  log_info("Load scenario {path}")
  .scenario <- if (grepl(".Rdata", name, fixed = TRUE)) {
    load(path)
    scenario$add_parameter(extract.parameters(iraceResults$parameters))
    if (nrow(iraceResults$allConfigurations) != 0) {
      exe <- execution$new(name = "execution-1")
      exe$set_irace_results(iraceResults)
      scenario$add_execution(exe)
    }
    aux <- iraceResults$scenario
    rm(iraceResults)
    aux
  } else {
    tryCatch({
      irace::readScenario(filename = path)
    }, error = function(err) {
      log_error("{err}")
      return(NULL)
    })
  }

  if (!onlyOptions) {
    if (is.null(.scenario)) {
      log_error("Can't load scenario file")
      return(FALSE)
    }

    path <- scenario$targetRunner
    if (checkPath(path)) {
      log_info("Add target runner from {path}")
      scenario$set_target_runner(paste(readLines(path), collapse = "\n"))
    }

    path <- scenario$targetEvaluator
    if (checkPath(path)) {
      log_info("Add target evaluator from {path}")
      scenario$set_target_evaluator(paste(readLines(path), collapse = "\n"))
    }

    path <- scenario$parameterFile
    parameters <- NULL
    if (checkPath(path) && nrow(scenario$get_parameters()) == 0) {
      log_info("Add parameters from {path}")
      parameters <- tryCatch({
        data <- irace::readParameters(file = path)
        scenario$add_parameter(extract.parameters(data))
        data
      }, error = function(err) {
        log_error("{err}")
      })
    }

    path <- scenario$forbiddenFile
    if (checkPath(path)) {
      log_info("Add forbidden file from {path}")
      tryCatch({
        irace:::readForbiddenFile(path)
        source <- readLines(path)
        scenario$add_forbidden(source)
      }, error = function(err) {
        log_error("{err}")
      })
    }

    path <- scenario$configurationsFile
    if (checkPath(path)) {
      log_info("Add initial configurations {path}")

      tryCatch({
        if (is.null(parameters)) {
          parameters <- parameters_as_irace(scenario$get_parameters())
        }
        config <- irace::readConfigurationsFile(filename = path, parameters = parameters)
        scenario$add_configuration(config)
      }, error = function(err) {
        log_error("{err}")
      })
    }
  }

  for (opt in names(.scenario)) {
    if (!availableOption(opt))
      next

    if (is.function(.scenario[[opt]]))
      next

    value = as.character(.scenario[[opt]])

    value = if (!grepl("\\D", value)) {
      as.numeric(value)
    } else {
      .scenario[[opt]]
    }

    log_info("{opt}: {as.character(.scenario[[opt]])}")
    scenario$add_irace_option(opt, value)
  }

  scenario$clear_scenario_temp()

  return(TRUE)
}

availableOption <- function(option) {
  if (option %in% scenarioOptions$id) {
    return(TRUE)
  }
  return(FALSE)
}

descentConfigurationTree <- function(iraceResults, configuration_id) {

  recursiveChilds <- function(id) {
    ids <- data.frame()
    childs <- subset(iraceResults$allConfigurations, .PARENT. == id, select = ".ID.")

    if (nrow(childs) == 0)
      return(ids)

    ids <- data.frame(from = id, to = childs$.ID.)

    for (row in seq_len(nrow(childs))) {
      childId <- childs[row,]
      ids <- rbind(ids, recursiveChilds(childId))
    }

    return(ids)
  }

  return(unique(recursiveChilds(configuration_id)))
}

configurationTrajectory <- function(iraceResults, configuration_id) {

  recursiveParents <- function(id) {
    ids <- data.frame()
    parent <- subset(iraceResults$allConfigurations, .ID. == id, select = ".PARENT.")$.PARENT.

    if (length(parent) == 0 || is.na(parent))
      return(ids)

    ids <- data.frame(from = id, to = parent)
    ids <- rbind(ids, recursiveParents(parent))

    return(ids)
  }

  return(recursiveParents(configuration_id))
}

treePlot <- function(data, title) {
  G <- graph_from_data_frame(data)

  vs <- V(G)
  es <- as.data.frame(get.edgelist(G, names = FALSE))
  node.data <- get.data.frame(G, what = "vertices")

  ne <- length(es[1]$V1)

  L <- layout_as_tree(G)
  Xn <- L[, 1]
  Yn <- L[, 2]

  tree <- plot_ly(
    x = ~Xn,
    y = ~Yn,
    type = "scatter",
    mode = "markers",
    text = vs$name,
    hoverinfo = "text",
    marker = list(
      color = as.factor(node.data$name),
      size = I(50)
    )
  )

  edge_shapes <- list()

  for (i in seq_len(ne)) {
    v0 <- es[i,]$V1
    v1 <- es[i,]$V2

    if (v0 == v1)
      next

      edge_shape <- list(
      type = "line",
      layer = "below",
      line = list(color = "#030303", width = 0.3),
      x0 = Xn[v0],
      y0 = Yn[v0],
      x1 = Xn[v1],
      y1 = Yn[v1]
    )

    edge_shapes[[i]] <- edge_shape
  }

  axis <- list(title = "", showgrid = FALSE, showticklabels = FALSE, zeroline = FALSE)

  plot_tree <- layout(
    tree,
    title = title,
    shapes = edge_shapes,
    xaxis = axis,
    yaxis = axis,
    showlegend = FALSE
  )

  return(plot_tree)
}