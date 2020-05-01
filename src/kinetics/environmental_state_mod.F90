module environmental_state_mod

  type environmental_state_type
    real :: number_density_air__num_m3, temperature, pressure
    real :: aerosol_surface_area_density(4), aerosol_diameter(4)
    real :: H2O_number_density__num_m3, O2_number_density__num_m3
  end type environmental_state_type

end module environmental_state_mod
