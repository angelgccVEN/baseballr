#' Get Play-By-Play Data for NCAA Baseball Games
#'
#' @param game_info_url The url for the game's play-by-play data.
#' This can be found using the get_ncaa_schedule_info function.
#'
#' @importFrom rvest html_nodes html_text html_table
#' @importFrom xml2 read_html
#' @importFrom tibble tibble
#' @importFrom tidyr gather spread
#' @importFrom purrr map
#' @importFrom janitor make_clean_names
#' @return A dataframe with play-by-play data for an individual
#' game.
#' @export
#'
#' @examples \dontrun{get_ncaa_schedule_info(736, 2019)}

get_ncaa_baseball_pbp <- function(game_info_url) {

  payload <- read_html(game_info_url) %>%
    rvest::html_nodes("#root li:nth-child(3) a") %>%
    rvest::html_attr("href") %>%
    as.data.frame() %>%
    dplyr::rename(pbp_url_slug = '.') %>%
    dplyr::mutate(pbp_url = paste0("https://stats.ncaa.org", pbp_url_slug)) %>%
    dplyr::pull(pbp_url)

  pbp_payload <- xml2::read_html(payload)

  game_info <- pbp_payload %>%
    rvest::html_nodes("table:nth-child(7)") %>%
    rvest::html_table() %>%
    as.data.frame() %>%
    tidyr::spread(X1, X2) %>%
    dplyr::rename_all(~gsub(":", "", .x)) %>%
    dplyr::rename_all(~janitor::make_clean_names(.x)) %>%
    dplyr::mutate(game_date = substr(game_date, 1, 10))

  if (!grepl("attendance", names(game_info))) {

    game_info$attendance <- NA
  } else {

    game_info <- game_info %>%
      dplyr::mutate(attendance = as.numeric(gsub(",", "", attendance)))
  }

  table_list <- pbp_payload %>%
    rvest::html_nodes("[class='mytable']")

  condition <- table_list %>%
    lapply(function(x) nrow(as.data.frame(x %>%
                                            rvest::html_table())) > 3)

  table_list_innings <- table_list[which(unlist(condition))]

  table_list_innings <- table_list_innings %>%
    setNames(seq(1,length(table_list_innings)))

  teams <- tibble::tibble(away = table_list_innings[[1]] %>%
                            rvest::html_table() %>%
                            as.data.frame() %>%
                            .[1,1],
                          home = table_list_innings[[1]] %>%
                            rvest::html_table() %>%
                            as.data.frame() %>%
                            .[1,3])

  format_baseball_pbp_tables <- function(table_node) {

    table <- table_node %>%
      rvest::html_table() %>%
      as.data.frame() %>%
      dplyr::filter(!grepl(pattern = "R:", x = X1)) %>%
      dplyr::mutate(batting = ifelse(X1 != "", teams$away, teams$home)) %>%
      dplyr::mutate(fielding = ifelse(X1 != "", teams$home, teams$away)) %>%
      .[-1,] %>%
      tidyr::gather(key = key, value = value, -c(batting, fielding, X2)) %>%
      dplyr::rename(score = X2) %>%
      dplyr::filter(value != "")

    table <- table %>%
      dplyr::rename(description = value) %>%
      dplyr::select(-key)

    table
  }

  mapped_table <- purrr::map(.x = table_list_innings,
                             ~format_baseball_pbp_tables(.x)) %>%
    dplyr::bind_rows(.id = "inning")

  mapped_table[1,2] <- ifelse(mapped_table[1,2] == "",
                              "0-0", mapped_table[1,2])

  mapped_table <- mapped_table %>%
    dplyr::mutate(score = ifelse(score == "", NA, score)) %>%
    tidyr::fill(score, .direction = "down")

  mapped_table <- mapped_table %>%
    dplyr::mutate(inning_top_bot = ifelse(teams$away == batting, "top", "bot"),
                  attendance = game_info$attendance,
                  date = game_info$game_date,
                  location = game_info$location) %>%
    dplyr::select(date, location, attendance, inning, inning_top_bot, dplyr::everything())

  mapped_table
}
