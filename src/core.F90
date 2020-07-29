! Copyright (C) 2020 National Center for Atmospheric Research
! SPDX-License-Identifier: Apache-2.0
!
!> \file
!> The micm_core module

!> The core_t type and related functions
module micm_core

  use micm_kinetics,                   only : kinetics_t
  use micm_ODE_solver,                 only : ODE_solver_t
  use musica_constants,                only : musica_dk, musica_ik
  use musica_domain,                   only : domain_state_mutator_ptr,       &
                                              domain_state_accessor_ptr,      &
                                              domain_state_accessor_t
  use musica_string,                   only : string_t


  implicit none
  private

  public :: core_t

  !> MICM core
  !!
  !! Top-level chemistry type. A core initializes the chemical scheme,
  !! solves for chemistry over given time steps, and finalizes chemistry
  !! objects.
  !!
  !! \todo ensure that MICM core is thread-safe
  type :: core_t
    private
    !> ODE solver
    class(ODE_solver_t), pointer :: ODE_solver_ => null( )
    !> Kinetics calculator
    class(kinetics_t), pointer :: kinetics_ => null( )
    !> Mutators for chemical species
    class(domain_state_mutator_ptr), pointer ::                               &
        species_mutators_(:) => null( )
    !> Accessors for chemical species
    class(domain_state_accessor_ptr), pointer ::                              &
        species_accessors_(:) => null( )
    !> Mutators for reaction rates
    class(domain_state_mutator_ptr), pointer ::                               &
        rate_mutators_(:) => null( )
    !> Environmental property accessors
    !! \todo move MICM environmental accessors to micm_environment module
    !! @{
    class(domain_state_accessor_t), pointer :: temperature__K_
    class(domain_state_accessor_t), pointer :: pressure__Pa_
    class(domain_state_accessor_t), pointer :: number_density_air__mol_m3_
    !> @}

    !> Working number density arrray [molec cm-3]
    real(kind=musica_dk), allocatable :: number_densities__molec_cm3_(:)
    !> Working reaction rate array [molec cm-3 s-1]
    real(kind=musica_dk), allocatable :: reaction_rates__molec_cm3_s_(:)
  contains
    !> Solve chemistry for one or more grid cells
    procedure :: solve
    !> Set the initial conditions for the current time step
    procedure, private :: time_step_initialize
    !> Finalize the chemistry core
    final :: finalize
  end type core_t

  !> Constructor
  interface core_t
    module procedure constructor
  end interface core_t

contains

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  !> MICM Core constructor
  !!
  !! Sets up chemistry objects for solving
  function constructor( config, domain, output ) result( new_obj )

    use micm_ODE_solver_factory,       only : ODE_solver_builder
    use musica_assert,                 only : assert
    use musica_config,                 only : config_t
    use musica_domain,                 only : domain_t
    use musica_io,                     only : io_t
    use musica_string,                 only : string_t

    !> New MICM Core
    type(core_t), pointer :: new_obj
    !> Chemistry configuration data
    class(config_t), intent(inout) :: config
    !> Model domain
    class(domain_t), intent(inout) :: domain
    !> Output file
    class(io_t), intent(inout) :: output

    character(len=*), parameter :: my_name = 'MICM chemistry constructor'
    integer :: i_spec, i_rxn
    type(string_t), allocatable :: accessor_names(:), species_names(:),       &
                                   reaction_names(:)
    type(config_t) :: solver_opts
    real(kind=musica_dk) :: chemistry_time_step__s

    allocate( new_obj )

    ! Get the chemistry time step
    call config%get( "chemistry time step", "s", chemistry_time_step__s,      &
                     my_name )

    ! Set up the kinetics calculator
    new_obj%kinetics_ => kinetics_t( )
    call new_obj%kinetics_%species_names( species_names )
    call new_obj%kinetics_%reaction_names( reaction_names )

    ! Set up the solver
    call config%get( "solver", solver_opts, my_name )
    call solver_opts%add( "chemistry time step", "s", chemistry_time_step__s, &
                          my_name )
    call solver_opts%add( "number of variables", size( species_names ),       &
                          my_name )
    new_obj%ODE_solver_ => ODE_solver_builder( solver_opts )

    ! Register state variables for the chemical species concentrations
    new_obj%species_mutators_ =>                                              &
      domain%register_cell_state_variable_set( "chemical_species",            & !- variable set name
                                               "mol m-3",                     & !- units
                                               0.0d0,                         & !- default value
                                               species_names,                 & !- variable element names
                                               my_name )
    new_obj%species_accessors_ =>                                             &
      domain%cell_state_set_accessor( "chemical_species",                     & !- variable set name
                                      "mol m-3",                              & !- units
                                      accessor_names,                         & !- variable element names
                                      my_name )

    ! Register state variables for reaction rates
    new_obj%rate_mutators_ =>                                                 &
      domain%register_cell_state_variable_set( "reaction_rates",              & !- variable set name
                                               "mol m-3 s-1",                 & !- units
                                               0.0d0,                         & !- default value
                                               reaction_names,                & !- variable element names
                                               my_name )

    ! Register accessors for environmental properties
    new_obj%temperature__K_ =>                                                &
      domain%cell_state_accessor( "temperature", "K", my_name )
    new_obj%pressure__Pa_ =>                                                  &
      domain%cell_state_accessor( "pressure", "Pa", my_name )
    new_obj%number_density_air__mol_m3_ =>                                    &
      domain%cell_state_accessor( "number density air", "mol m-3",   &
                                           my_name )

    ! Register the chemical species concentrations for output
    call assert( 415788666, size( species_names ) .eq.                        &
                            size( accessor_names ) )
    do i_spec = 1, size( species_names )
      call assert( 359403346, species_names( i_spec ) .eq.                    &
                              accessor_names( i_spec ) )
      call output%register( domain,                                           &
                            "chemical_species%"//                             & !- variable full name
                                species_names( i_spec )%to_char( ),           &
                            "mol m-3",                                        & !- units
                            "CONC."//species_names( i_spec )%to_char( ) )       !- output name
    end do

    ! Register the reaction rates for output
    do i_rxn = 1, size( reaction_names )
      call output%register( domain,                                           &
                            "reaction_rates%"//                               & !- variable full name
                                reaction_names( i_rxn )%to_char( ),           &
                            "mol m-3 s-1",                                    & !- units
                            "RATE."//reaction_names( i_rxn )%to_char( ) )       !- output name
    end do

    ! Set up arrays for use during solving
    allocate( new_obj%number_densities__molec_cm3_( size( species_names ) ) )
    allocate( new_obj%reaction_rates__molec_cm3_s_( size( reaction_names ) ) )

    ! clean up
    call solver_opts%finalize( )

  end function constructor

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  !> Solve chemistry for a given number of grid cells and time step
  subroutine solve( this, domain_state, cell, current_time__s, time_step__s )

    use musica_assert,                 only : assert_msg
    use musica_constants,              only : kAvagadro
    use musica_domain,                 only : domain_state_t,                 &
                                              domain_iterator_t
    use musica_string,                 only : to_char

    !> MICM chemistry
    class(core_t), intent(inout) :: this
    !> Domain state
    class(domain_state_t), intent(inout) :: domain_state
    !> Grid cell to solve
    class(domain_iterator_t), intent(in) :: cell
    !> Current simulation time [s]
    real(kind=musica_dk), intent(in) :: current_time__s
    !> Chemistry time step [s]
    real(kind=musica_dk), intent(in) :: time_step__s

    integer(kind=musica_ik) :: i_spec, i_rxn, error_flag

    ! Set the initial conditions for the time step
    call this%time_step_initialize( domain_state, cell )

    ! solve the chemistry for this time step
    call this%ODE_solver_%solve( TStart = current_time__s,                    &
                                 TEnd   = current_time__s + time_step__s,     &
                                 y      = this%number_densities__molec_cm3_,  &
                                 theKinetics = this%kinetics_,                &
                                 IErr   = error_flag )

    call assert_msg( 534725427, error_flag .eq. 0,                            &
                     "Chemistry solver failed with code "//                   &
                     to_char( error_flag ) )

    ! update the species concentrations [mol m-3]
    do i_spec = 1, size( this%species_mutators_ )
      call domain_state%update( cell,                                         &
                                this%species_mutators_( i_spec )%val_,        &
                                this%number_densities__molec_cm3_( i_spec ) / &
                                    kAvagadro * 1.0d6 )
    end do

    ! save the reaction rates [mol m-3 s-1]
    this%reaction_rates__molec_cm3_s_ =                                       &
        this%kinetics_%reaction_rates( this%number_densities__molec_cm3_ )
    do i_rxn = 1, size( this%reaction_rates__molec_cm3_s_ )
      call domain_state%update( cell,                                         &
                                this%rate_mutators_( i_rxn )%val_,            &
                                this%reaction_rates__molec_cm3_s_( i_rxn ) /  &
                                    kAvagadro * 1.0d6 )
    end do

  end subroutine solve

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  !> Set initial conditions for current time step
  !!
  !! Sets environmental conditions and calculates rate constants
  subroutine time_step_initialize( this, domain_state, cell )

    use micm_environment,              only : environment_t
    use musica_constants,              only : kAvagadro
    use musica_domain,                 only : domain_state_t,                 &
                                              domain_iterator_t

    !> MICM chemistry
    class(core_t), intent(inout) :: this
    !> Domain state
    class(domain_state_t), intent(inout) :: domain_state
    !> Grid cell to solve
    class(domain_iterator_t), intent(in) :: cell

    integer :: i_spec
    type(environment_t) :: env

    ! get the current environmental conditions
    call domain_state%get( cell, this%temperature__K_, env%temperature )
    call domain_state%get( cell, this%pressure__Pa_,   env%pressure )
    call domain_state%get( cell, this%number_density_air__mol_m3_,            & ! currently in [mol m-3]
                           env%number_density_air )

    ! convert air density to non-standard units currently used in MICM
    ! [molec cm-3]
    env%number_density_air = env%number_density_air * kAvagadro * 1.0d-6

    ! get the current species concentrations [mol m-3]
    ! and convert to non-standard units currently used in MICM [molec cm-3]
    !> \todo update MICM to use [mol m-3] for number densities
    do i_spec = 1, size( this%species_accessors_ )
      call domain_state%get( cell,                                            &
                             this%species_accessors_( i_spec )%val_,          &
                             this%number_densities__molec_cm3_( i_spec ) )
      this%number_densities__molec_cm3_( i_spec ) =                           &
          this%number_densities__molec_cm3_( i_spec ) * kAvagadro * 1.0d-6
    end do

    ! update the kinetics for the current conditions
    call this%kinetics_%update( env )

  end subroutine time_step_initialize

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  !> Finalize the chemistry core
  subroutine finalize( this )

    !> MICM chemistry
    type(core_t), intent(inout) :: this

    if( associated( this%ODE_solver_ ) )                                      &
      deallocate( this%ODE_solver_ )
    if( associated( this%kinetics_ ) )                                        &
      deallocate( this%kinetics_ )
    if( associated( this%species_mutators_ ) )                                &
      deallocate( this%species_mutators_ )
    if( associated( this%species_accessors_ ) )                               &
      deallocate( this%species_accessors_ )
    if( associated( this%rate_mutators_ ) )                                   &
      deallocate( this%rate_mutators_ )
    if( associated( this%temperature__K_ ) )                                  &
      deallocate( this%temperature__K_ )
    if( associated( this%pressure__Pa_ ) )                                    &
      deallocate( this%pressure__Pa_ )
    if( associated( this%number_density_air__mol_m3_ ) )                      &
      deallocate( this%number_density_air__mol_m3_ )

  end subroutine finalize

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

end module micm_core