IraceOutputView <- R6::R6Class(
  classname = "IraceOutputView",
  inherit = View,
  public = list(
    iraceButton = NULL,
    execution = NULL,

    initialize = function(id) {
      super$initialize(id)
      self$iraceButton <- IraceButton$new()
    },

    ui = function() {
      ns <- NS(self$id)

      tagList(
        
        fluidRow(
          class = "sub-header",
          column(
            width = 10,
            h2("Irace Output"), 
            p("See here the progress of the current irace execution. Click on start to launch irace."),
            p("You will be asked to assign a name to your execution, 
              in this way you may execute your scenario more than once.")
          ),
          column(
            width = 2,
            class = "d-flex align-items-center justify-content-end",
            self$iraceButton$ui(inputId = ns("start_irace"))
          )
        ),
        fluidRow(
          bs4Card(
            inputId = ns("target"),
            collapsible = FALSE,
            closable = FALSE,
            width = 12,
            verbatimTextOutput(outputId = ns("irace_output"))
          # tags$head(
          #  tags$style(
          #    sprintf("#%s{overflow-y:scroll; max-height:550px;}", ns("irace_output"))
          #  ),
          #  tags$script(
          #    sprintf(
          #      '
          #      Shiny.addCustomMessageHandler("iraceOuputScroll", function (x) {
          #        var obj = document.getElementById("%s");
          #        obj.scrollTop = obj.scrollHeight;
          #      });
          #      ',
          #      ns("irace_output")
          #    )
          #  )
          # )
          )
        )
      )
    },

    server = function(input, output, session, store) {
      values <- reactiveValues(
        source = NULL,
        timer = reactiveTimer(intervalMs = 900) # Change refresh timer for running log
      )

      start <- self$iraceButton$call(id = "start_irace", store = store)

      observeEvent(start$action, {
        if (store$startIrace) {
          store$startIrace <- FALSE
          store$iraceProcess$kill_tree()
          store$iraceProcess$finalize()
        } else {
          shinyalert(
            title = "Execution name",
            text = "Give a name to identify the execution after.",
            type = "input",
            inputType = "text",
            showCancelButton = TRUE,
            closeOnEsc = FALSE,
            callbackR = function(name) {
              if (is.logical(name) && !name) {
                return(invisible())
              }

              if (is.null(name) || name == "") {
                alert.error("Give a name.")
                return(invisible())
              }

              run_irace(store, name)

              if (store$startIrace) {
                self$execution <- execution$new(name = name)
              }
            }
          )
        }
      })

      observe({
        if (!store$startIrace) {
          return(invisible())
        }

        store$iraceAlive()

        if (!store$iraceProcess$is_alive()) {
          log_info("Irace end.")
          enable(id = "scenarioPicker")

          if (!get_option("debug", FALSE)) {
            unlink(pkg$tempFolder, recursive = TRUE, force = TRUE)
          }

          store$iraceProcess$poll_io(1500)
          error <- store$iraceProcess$read_error_lines()

          if (get_option("debug", FALSE)) {
            log_error("Optional: {error}")
          }

          log <- gsub('"', "", store$pg$get_irace_option("logFile"))

          if (file.exists(log)) {
            load(log)

            if (nrow(iraceResults$allConfigurations) != 0) {
              self$execution$set_irace_results(iraceResults)

              if (file.exists(pkg$outputLog)) {
                self$execution$set_output_log(paste(readLines(pkg$outputLog), collapse = "\n"))
              }

              store$pg$add_execution(self$execution)

              shinyalert(title = "The execution has ended", type = "success", timer = 1500)
            } else {
              file.remove(log)
              file.remove(pkg$outputLog)

              if (!is.null(error) && error != "" && length(error) > 0) {
                log_error("Stop irace with error: {error}")
                alert.error(paste(error, collapse = "\n"))
                self$execution <- NULL
              }
            }

            rm(iraceResults)
          } else {
            if (!is.null(error) && error != "" && length(error) > 0) {
              log_error("Stop irace with error: {error}")
              alert.error(paste(error, collapse = "\n"))
              self$execution <- NULL
            }
          }

          store$pg$clear_scenario_temp()

          store$iraceProcess <- NULL
          store$startIrace <- FALSE
        }
      })

      observe({
        playground_emitter$value(playground_events$current_scenario)

        if (!store$startIrace) {
          if (!is.null(pkg$outputLog) && file.exists(pkg$outputLog)) {
            values$source <- paste(readLines(pkg$outputLog), collapse = "\n")
          } else {
            values$source <- ""
          }
          return(invisible())
        }

        values$timer()

        future({
          if (file.exists(pkg$outputLog)) {
            paste(readLines(pkg$outputLog), collapse = "\n")
          } else {
            ""
          }
        }) %...>% {
          values$source <- .
        }

        # session$sendCustomMessage(type = "iraceOuputScroll", 1)
      })

      output$irace_output <- renderText({
        shiny::validate(
          need(values$source, message = "Irace is not running yet.")
        )
        values$source
      })
    }
  )
)