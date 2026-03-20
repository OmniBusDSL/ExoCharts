#' ExoGridChart R Package
#'
#' Real-time cryptocurrency market data streaming SDK for R
#'
#' @import Rcpp
#' @useDynLib exogrid
#'
#' @examples
#' \dontrun{
#'   exo <- ExoGrid$new(host = "localhost", port = 9090)
#'   exo$connect()
#'   exo$get_tick_count()
#' }
#'
#' @export
ExoGrid <- R6::R6Class("ExoGrid",
  private = list(
    host = "localhost",
    port = 9090,
    connected = FALSE
  ),
  public = list(
    initialize = function(host = "localhost", port = 9090) {
      private$host <- host
      private$port <- port
      invisible(self)
    },

    connect = function() {
      .Call("exo_r_init")
      private$connected <- TRUE
      invisible(self)
    },

    disconnect = function() {
      .Call("exo_r_deinit")
      private$connected <- FALSE
      invisible(self)
    },

    start = function(exchanges = 7) {
      .Call("exo_r_start", as.integer(exchanges))
      invisible(self)
    },

    stop = function() {
      .Call("exo_r_stop")
      invisible(self)
    },

    get_tick_count = function() {
      .Call("exo_r_get_tick_count")
    },

    get_matrix_stats = function(ticker_id = 0L) {
      .Call("exo_r_get_matrix_stats", as.integer(ticker_id))
    }
  )
)
