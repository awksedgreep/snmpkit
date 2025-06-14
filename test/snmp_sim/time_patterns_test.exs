defmodule SnmpKit.SnmpSim.TimePatternsTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.TimePatterns

  describe "Daily Utilization Patterns" do
    test "returns low utilization during early morning hours" do
      early_morning = ~U[2024-01-15 03:00:00Z]

      factor = TimePatterns.get_daily_utilization_pattern(early_morning)

      assert factor >= 0.2
      assert factor <= 0.4
    end

    test "returns high utilization during business hours" do
      # 2 PM
      business_hours = ~U[2024-01-15 14:00:00Z]

      factor = TimePatterns.get_daily_utilization_pattern(business_hours)

      assert factor >= 0.8
      assert factor <= 1.3
    end

    test "returns peak utilization during evening hours" do
      # 7 PM
      evening_peak = ~U[2024-01-15 19:00:00Z]

      factor = TimePatterns.get_daily_utilization_pattern(evening_peak)

      assert factor >= 1.2
      # Can include bursts
      assert factor <= 1.8
    end

    test "handles smooth transitions between time periods" do
      # Test transition from morning to business hours
      morning_end = ~U[2024-01-15 08:30:00Z]
      business_start = ~U[2024-01-15 09:30:00Z]

      morning_factor = TimePatterns.get_daily_utilization_pattern(morning_end)
      business_factor = TimePatterns.get_daily_utilization_pattern(business_start)

      # Should be a smooth transition, not abrupt jump
      assert abs(business_factor - morning_factor) < 0.5
    end
  end

  describe "Weekly Pattern Variations" do
    test "returns full pattern for weekdays" do
      # Tuesday at 2 PM
      tuesday = ~U[2024-01-16 14:00:00Z]

      factor = TimePatterns.get_weekly_pattern(tuesday)

      assert factor >= 0.9
      assert factor <= 1.1
    end

    test "returns reduced pattern for Saturday" do
      # Saturday at 2 PM
      saturday = ~U[2024-01-20 14:00:00Z]

      factor = TimePatterns.get_weekly_pattern(saturday)

      assert factor >= 0.6
      assert factor <= 0.9
    end

    test "returns lowest pattern for Sunday" do
      # Sunday at 2 PM
      sunday = ~U[2024-01-21 14:00:00Z]

      factor = TimePatterns.get_weekly_pattern(sunday)

      assert factor >= 0.3
      assert factor <= 0.7
    end

    test "varies by day of week for weekdays" do
      monday = ~U[2024-01-15 14:00:00Z]
      tuesday = ~U[2024-01-16 14:00:00Z]
      friday = ~U[2024-01-19 14:00:00Z]

      monday_factor = TimePatterns.get_weekly_pattern(monday)
      tuesday_factor = TimePatterns.get_weekly_pattern(tuesday)
      friday_factor = TimePatterns.get_weekly_pattern(friday)

      # Tuesday should be peak efficiency
      assert tuesday_factor >= monday_factor
      assert tuesday_factor >= friday_factor

      # Friday should be lower (early wind-down)
      assert friday_factor < tuesday_factor
    end
  end

  describe "Temperature Patterns" do
    test "returns seasonal temperature variations" do
      # January (winter)
      winter = ~U[2024-01-15 12:00:00Z]
      # July (summer)
      summer = ~U[2024-07-15 12:00:00Z]

      winter_offset = TimePatterns.get_seasonal_temperature_pattern(winter)
      summer_offset = TimePatterns.get_seasonal_temperature_pattern(summer)

      # Winter should be colder (negative offset)
      assert winter_offset < 0
      # Summer should be warmer (positive offset)
      assert summer_offset > 0

      # Difference should be significant (seasonal variation)
      assert summer_offset - winter_offset > 20
    end

    test "returns daily temperature variations" do
      # 6 AM (coldest)
      early_morning = ~U[2024-01-15 06:00:00Z]
      # 3 PM (warmest)
      afternoon = ~U[2024-01-15 15:00:00Z]

      morning_offset = TimePatterns.get_daily_temperature_pattern(early_morning)
      afternoon_offset = TimePatterns.get_daily_temperature_pattern(afternoon)

      # Morning should be cooler
      assert morning_offset < 0
      # Afternoon should be warmer
      assert afternoon_offset > 0

      # Should have reasonable daily range
      assert afternoon_offset - morning_offset > 5
      assert afternoon_offset - morning_offset < 15
    end
  end

  describe "Weather Impact Simulation" do
    test "returns weather impact factors" do
      datetime = ~U[2024-01-15 14:00:00Z]

      # Run multiple times to test randomness
      factors =
        for _ <- 1..10 do
          TimePatterns.apply_weather_variation(datetime)
        end

      # All factors should be between 0.5 and 1.2
      assert Enum.all?(factors, fn factor -> factor >= 0.5 and factor <= 1.2 end)

      # Should have some variation (not all the same)
      unique_factors = Enum.uniq(factors)
      assert length(unique_factors) > 1
    end

    test "varies weather probability by season" do
      winter = ~U[2024-01-15 14:00:00Z]
      spring = ~U[2024-04-15 14:00:00Z]
      summer = ~U[2024-07-15 14:00:00Z]
      fall = ~U[2024-10-15 14:00:00Z]

      # Test multiple iterations to see seasonal differences
      seasons = [winter, spring, summer, fall]

      for season <- seasons do
        factor = TimePatterns.apply_weather_variation(season)
        assert factor >= 0.5
        assert factor <= 1.2
      end
    end
  end

  describe "Seasonal Variations" do
    test "applies equipment stress patterns" do
      summer = ~U[2024-07-15 12:00:00Z]
      winter = ~U[2024-01-15 12:00:00Z]
      spring = ~U[2024-04-15 12:00:00Z]

      summer_stress = TimePatterns.apply_seasonal_variation(summer, :equipment_stress)
      winter_stress = TimePatterns.apply_seasonal_variation(winter, :equipment_stress)
      spring_stress = TimePatterns.apply_seasonal_variation(spring, :equipment_stress)

      # Summer and winter should have higher stress
      assert summer_stress > spring_stress
      assert winter_stress > spring_stress

      # Summer should be highest stress
      assert summer_stress >= winter_stress
    end

    test "applies power consumption patterns" do
      summer = ~U[2024-07-15 12:00:00Z]
      winter = ~U[2024-01-15 12:00:00Z]
      spring = ~U[2024-04-15 12:00:00Z]

      summer_power = TimePatterns.apply_seasonal_variation(summer, :power_consumption)
      winter_power = TimePatterns.apply_seasonal_variation(winter, :power_consumption)
      spring_power = TimePatterns.apply_seasonal_variation(spring, :power_consumption)

      # Winter should be highest (heating)
      assert winter_power > summer_power
      assert winter_power > spring_power

      # Summer should be higher than spring (cooling)
      assert summer_power > spring_power
    end

    test "applies generic seasonal patterns" do
      dates = [
        ~U[2024-01-15 12:00:00Z],
        ~U[2024-04-15 12:00:00Z],
        ~U[2024-07-15 12:00:00Z],
        ~U[2024-10-15 12:00:00Z]
      ]

      factors = Enum.map(dates, &TimePatterns.apply_seasonal_variation(&1, :generic))

      # All factors should be between 0.9 and 1.1 (±10%)
      assert Enum.all?(factors, fn factor -> factor >= 0.9 and factor <= 1.1 end)

      # Should have variation across seasons
      min_factor = Enum.min(factors)
      max_factor = Enum.max(factors)
      assert max_factor - min_factor > 0.1
    end
  end

  describe "Interface Traffic Rates" do
    test "returns appropriate rates for different interface types" do
      datetime = ~U[2024-01-15 14:00:00Z]

      ethernet_rates = TimePatterns.get_interface_traffic_rate(:ethernet_gigabit, datetime)
      docsis_rates = TimePatterns.get_interface_traffic_rate(:docsis_downstream, datetime)
      cellular_rates = TimePatterns.get_interface_traffic_rate(:cellular_lte, datetime)

      {eth_min, eth_max, eth_factor} = ethernet_rates
      {docsis_min, docsis_max, docsis_factor} = docsis_rates
      {cell_min, cell_max, cell_factor} = cellular_rates

      # Gigabit Ethernet should support high rates
      # 125 MB/s
      assert eth_max == 125_000_000

      # DOCSIS should support even higher rates
      assert docsis_max > eth_max

      # Cellular should be lower
      assert cell_max < eth_max

      # All should have reasonable factors
      assert eth_factor >= 0.1 and eth_factor <= 2.0
      assert docsis_factor >= 0.1 and docsis_factor <= 2.0
      assert cell_factor >= 0.1 and cell_factor <= 2.0
    end

    test "applies time-based factors to traffic rates" do
      # Tuesday 2 PM
      business_hour = ~U[2024-01-15 14:00:00Z]
      # Tuesday 3 AM
      late_night = ~U[2024-01-15 03:00:00Z]

      {_, _, business_factor} =
        TimePatterns.get_interface_traffic_rate(:ethernet_gigabit, business_hour)

      {_, _, night_factor} =
        TimePatterns.get_interface_traffic_rate(:ethernet_gigabit, late_night)

      # Business hours should have higher factor
      assert business_factor > night_factor
    end
  end

  describe "Edge Cases and Robustness" do
    test "handles boundary times correctly" do
      # Test exactly at midnight
      midnight = ~U[2024-01-15 00:00:00Z]

      daily_factor = TimePatterns.get_daily_utilization_pattern(midnight)
      weekly_factor = TimePatterns.get_weekly_pattern(midnight)

      assert is_float(daily_factor)
      assert is_float(weekly_factor)
      assert daily_factor > 0
      assert weekly_factor > 0
    end

    test "handles leap year dates correctly" do
      leap_year_date = ~U[2024-02-29 12:00:00Z]

      seasonal_temp = TimePatterns.get_seasonal_temperature_pattern(leap_year_date)
      daily_temp = TimePatterns.get_daily_temperature_pattern(leap_year_date)

      assert is_float(seasonal_temp)
      assert is_float(daily_temp)
    end

    test "produces consistent results for same input" do
      datetime = ~U[2024-01-15 14:00:00Z]

      # Same input should produce same deterministic output
      # (except for weather which includes randomness)
      factor1 = TimePatterns.get_daily_utilization_pattern(datetime)
      factor2 = TimePatterns.get_daily_utilization_pattern(datetime)

      assert factor1 == factor2

      weekly1 = TimePatterns.get_weekly_pattern(datetime)
      weekly2 = TimePatterns.get_weekly_pattern(datetime)

      assert weekly1 == weekly2
    end
  end
end
