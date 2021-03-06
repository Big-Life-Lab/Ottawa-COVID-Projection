short_term_forecast <- function(data,
                                parameter,
                                parameter_weight = 1,
                                start_date,
                                end_date,
                                omit_last_date = FALSE,
                                generation_time,
                                incubation_period,
                                reporting_delay,
                                output = "projections"){
  # Format dataset
  if(missing(end_date)) {
    end_date <- max(as.Date(data$date), na.rm = TRUE)
  }
  
  data_formatted <- data %>%
    filter(as.Date(date) >= as.Date(start_date)) %>%
    filter(as.Date(date) <= as.Date(end_date)) %>%
    select(date, as.character(parameter)) %>%
    rename(confirm = as.character(parameter)) %>%
    mutate(date = as.Date(date),
           confirm = as.integer(confirm * parameter_weight))
  
  if(isTRUE(omit_last_date)){
    data_formatted <- data_formatted[data_formatted$date < as.Date(end_date),]
  }
  
  # Run epinow2 sim 
  projections <-
      EpiNow2::epinow(reported_cases = data_formatted, 
                      generation_time = generation_time,
                      delays = delay_opts(incubation_period, reporting_delay),
                      rt = rt_opts(prior = list(mean = 2, sd = 0.2), rw = 7),
                      stan = stan_opts(cores = 4),
                      gp = NULL, horizon = 14)
  # Extract output
  if(output == as.character("projections")){
    forecast <-
      # Obtain summarized projections
      projections[[1]][[2]] %>%
      # Divide by the parameter weight
      mutate(median = ifelse(variable == "infections" | variable == "prior_infections" |
                               variable == "reported_cases",
                             median/parameter_weight, median),
             mean = ifelse(variable == "infections" | variable == "prior_infections" |
                             variable == "reported_cases",
                           mean/parameter_weight, mean),
             sd = ifelse(variable == "infections" | variable == "prior_infections" |
                           variable == "reported_cases",
                         sd/parameter_weight, sd),
             lower_90 = ifelse(variable == "infections" | variable == "prior_infections" |
                                 variable == "reported_cases",
                               lower_90/parameter_weight, lower_90),
             lower_50 = ifelse(variable == "infections" | variable == "prior_infections" |
                                 variable == "reported_cases",
                               lower_50/parameter_weight, lower_50),
             lower_20 = ifelse(variable == "infections" | variable == "prior_infections" |
                                 variable == "reported_cases",
                               lower_20/parameter_weight, lower_20),
             upper_90 = ifelse(variable == "infections" | variable == "prior_infections" |
                                 variable == "reported_cases",
                               upper_90/parameter_weight, upper_90),
             upper_50 = ifelse(variable == "infections" | variable == "prior_infections" |
                                 variable == "reported_cases",
                               upper_50/parameter_weight, upper_50),
             upper_20 = ifelse(variable == "infections" | variable == "prior_infections" |
                                 variable == "reported_cases",
                               upper_20/parameter_weight, upper_20))
  }  
  else if(output == as.character("estimates")){
    forecast <-
      projections[[3]][[3]] # Obtain numeric estimates
  }
  else if(output == as.character("both")){
    forecast <- list(
      projections[[1]][[2]] %>%
        # Divide by the parameter weight
        mutate(median = ifelse(variable == "infections" | variable == "prior_infections" |
                                 variable == "reported_cases",
                               median/parameter_weight, median),
               mean = ifelse(variable == "infections" | variable == "prior_infections" |
                               variable == "reported_cases",
                             mean/parameter_weight, mean),
               sd = ifelse(variable == "infections" | variable == "prior_infections" |
                             variable == "reported_cases",
                           sd/parameter_weight, sd),
               lower_90 = ifelse(variable == "infections" | variable == "prior_infections" |
                                   variable == "reported_cases",
                                 lower_90/parameter_weight, lower_90),
               lower_50 = ifelse(variable == "infections" | variable == "prior_infections" |
                                   variable == "reported_cases",
                                 lower_50/parameter_weight, lower_50),
               lower_20 = ifelse(variable == "infections" | variable == "prior_infections" |
                                   variable == "reported_cases",
                                 lower_20/parameter_weight, lower_20),
               upper_90 = ifelse(variable == "infections" | variable == "prior_infections" |
                                   variable == "reported_cases",
                                 upper_90/parameter_weight, upper_90),
               upper_50 = ifelse(variable == "infections" | variable == "prior_infections" |
                                   variable == "reported_cases",
                                 upper_50/parameter_weight, upper_50),
               upper_20 = ifelse(variable == "infections" | variable == "prior_infections" |
                                   variable == "reported_cases",
                                 upper_20/parameter_weight, upper_20)),
      projections[[3]][[3]]
    )
  }  

  return(forecast)
}

short_term_plot <- function(projections,
                            levels = c("historic", "forecast"),
                            obs_data,
                            obs_column,
                            forecast_type,
                            start_date = first(as.Date(projections$date)),
                            ylab,
                            title,
                            scale = FALSE){
  
  # Filter data based on forecast type and remove 50% CI
  projections <- projections %>%
    filter(variable == as.character(forecast_type)) %>%
    select(-c(lower_50, upper_50, lower_20, upper_20))
  
  # Omit last day of observed data
  obs_data_omit <- obs_data %>%
    filter(date < as.Date(last(date)))
  
  # Set types to levels indicated in function call
  projections$type[projections$date <= as.Date(last(obs_data_omit$date))] <-
    as.character(levels[[1]])
  
  projections$type[projections$date > as.Date(last(obs_data_omit$date))] <-
    as.character(levels[[2]])
  
  projections$type <- factor(projections$type, levels =
                               c(as.character(levels[[1]]), as.character(levels[[2]])))
  
  # set up CrI index
  CrIs <- extract_CrIs(projections)
  index <- 1
  alpha_per_CrI <- 0.6 / (length(CrIs) - 1)
  
  # Modify CI column names in dataset
  colnames(projections) <- reduce2(c("_", "0"), c(" ", "0%"),
                                   .init = colnames(projections),
                                   str_replace)
  # Set up ggplot object
  plot<- 
    ggplot(projections[as.Date(projections$date) >= as.Date(start_date),],
           aes(x = date, col = type, fill = type))
  
  # Add observed data if R is not specified
  obs_plot <- filter(obs_data_omit, as.Date(date) >= start_date)
  y_col <- obs_plot[[as.character(obs_column)]]
  if(forecast_type != as.character("R")){
    plot <- plot +
      geom_col(data = 
                 obs_plot[as.Date(obs_plot$date) >= as.Date(start_date),],
               aes(x = as.Date(date),
                   y = y_col,
                   text = paste("Observed:",
                                y_col)),
               fill = "#008080", col = "white", alpha = 0.5,
               show.legend = FALSE, na.rm = TRUE)
  }
  
  # plot v line for last observed date
  historic <- projections[projections$type == levels[[1]],]
  plot <- plot +
    geom_vline(
      xintercept = 
        as.numeric(last(historic$date)),
      linetype = 2)
  
  # plot median line
  plot <- plot +
    geom_line(aes(y = median),
              lwd = 0.9)
  
  # plot CrIs
  for (CrI in CrIs) {
    bottom <- paste("lower", paste0(CrI, "%"))
    top <-  paste("upper", paste0(CrI, "%"))
      plot <- plot +
        geom_ribbon(ggplot2::aes(ymin = .data[[bottom]], ymax = .data[[top]]), 
                             alpha = 0.2, size = 0.05)
    
  }
  
  # Set custom palette
  palette <- brewer.pal(name = "Dark2", n = 8)[c(1,3)]
  
  # add plot theming
  plot <- plot +
    theme(
      panel.background = element_blank(),
      panel.grid.major.y = element_line(colour = "grey"),
      axis.line.x = element_line(colour = "grey"),
      legend.position = "bottom",
      legend.title = element_blank(),
      plot.title = element_text(hjust = 0.5)) +
    scale_color_manual(values = palette) +
    scale_fill_manual(values = palette) +
    labs(y = ylab, x = "Date", col = "Type", fill = "Type", title = title) +
    expand_limits(y = c(-0.4, 0.8)) + 
    scale_x_date(expand = c(0,0), date_breaks = "1 week",
                 date_labels = "%b %d") +
    scale_y_continuous(expand = c(0, 0)) 
  
  # Convert to plotly object
  plot <- plotly::ggplotly(plot, tooltip = c("date", "text", "median",
                                             "lower 90%", "upper 90%"))
  
  
  # Set date display constraints
  if(as.numeric(as.Date(first(projections$date))) > as.Date(last(projections$date) - 40)){
    a <- as.numeric(as.Date(first(projections$date)))
  }
  else{
    a <- as.numeric(as.Date(last(projections$date) - 40)) 
  }
  b <- as.numeric(as.Date(last(projections$date)))
  
  # Format legend layout & add annotation
  plot <- plotly::layout(plot,
                         xaxis = list(range = c(a, b)),
                         legend = list(
                           #orientation = "h",
                           x = 0.02, y = 1
                         ),
                         annotations = list(
                           x = 1, y = -0.12, text = "*Shaded area represents the 90% credible region", 
                           showarrow = F, xref='paper', yref='paper', 
                           xanchor='right', yanchor='auto', xshift=0, yshift=0,
                           font=list(size=10)
                         ),
                         dragmode = "pan")
  
  if(isTRUE(scale)){
    tmp <- 1.75*max(projections$mean, na.rm = TRUE)
    plot <- layout(plot, 
                   yaxis = list(range = c(0, tmp)))
  }
  
  return(plot)
}