!-----------------------------------------------------------------------
! Copyright (c) 2011-2016  Remko Scharroo
! See LICENSE.TXT file for copying and redistribution conditions.
!
! This program is free software: you can redistribute it and/or modify
! it under the terms of the GNU Lesser General Public License as
! published by the Free Software Foundation, either version 3 of the
! License, or (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!-----------------------------------------------------------------------

!*rads_gen_j1 -- Converts Jason-1 data to RADS
!+
program rads_gen_j1

! This program reads Jason-1 (I)GDR files and converts them to the RADS format,
! written into files $RADSDATAROOT/data/j1/a/j1pPPPPcCCC.nc.
!  PPPP = relative pass number
!   CCC = cycle number
!
! syntax: rads_gen_j1 [options] < list_of_JASON1_file_names
!
! This program handles Jason-1 IGDR and GDR files in netCDF format,
! version C and E (also known as GDR-C and GDR-E).
! The format is described in:
!
! [1] IGDR and GDR Jason Products, AVISO and PODAAC User Handbook,
!     SMM-MU-M5-OP-13184-CN (AVISO), JPL D-21352 (PODAAC),
!     Edition 4.0, June 2008
!-----------------------------------------------------------------------
!
! Variables array fields to be filled are:
! time - Time since 1 Jan 85
! lat - Latitude
! lon - Longitude
! alt_eiggl04s/alt_gdre - Orbit altitude
! alt_rate - Orbit altitude rate
! range_* - Ocean range (retracked)
! dry_tropo_ecmwf - ECMWF dry tropospheric correction
! wet_tropo_ecmwf - ECMWF wet tropo correction
! wet_tropo_rad - Radiometer wet tropo correction
! iono_alt_ku - Dual-frequency ionospheric correction
! iono_gim - GIM ionosphetic correction
! inv_bar_static - Inverse barometer
! inv_bar_mog2d - MOG2D
! ssb_cls_* - SSB
! swh_* - Significant wave height
! sig0_* - Sigma0
! wind_speed_alt_ku - Altimeter wind speed
! wind_speed_rad - Radiometer wind speed
! wind_speed_ecmwf_u - ECMWF wind speed (U)
! wind_speed_ecmwf_v - ECMWF wind speed (V)
! range_rms_* - Std dev of range
! range_numval_* - Nr of averaged range measurements
! topo_dtm2000 - Bathymetry
! tb_187 - Brightness temperature (18.7 GHz)
! tb_238 - Brightness temperature (23.8 GHz)
! tb_340 - Brightness temperature (34.0 GHz)
! flags - Engineering flags
! swh_rms_* - Std dev of SWH
! sig0_rms_* - Std dev of sigma0
! off_nadir_angle2_wf_ku - Mispointing from waveform squared
! off_nadir_angle2_pf - Mispointing from platform squared
! rad_liquid_water - Liquid water content
! rad_water_vapor - Water vapor content
!
! Extionsions _* are:
! _ku:      Ku-band retracked with MLE4
! _c:       C-band
!-----------------------------------------------------------------------
use rads
use rads_devel
use rads_devel_netcdf
use rads_gen
use rads_misc
use rads_netcdf
use rads_time
use netcdf

! Command line arguments

integer(fourbyteint) :: ios, i, j, q, r
character(len=rads_cmdl) :: infile, arg
character(len=1) :: phasenm = ''

! Header variables

integer(fourbyteint) :: cyclenr, passnr, varid
real(eightbytereal) :: equator_time
logical :: cma92 = .false., gdre = .false.

! Other local variables

real(eightbytereal), parameter :: sec2000=473299200d0	! UTC seconds from 1 Jan 1985 to 1 Jan 2000

! Initialise

call synopsis
call rads_gen_getopt ('j1')
call synopsis ('--head')
call rads_init (S, sat)

!----------------------------------------------------------------------
! Read all file names from standard input
!----------------------------------------------------------------------

do
	read (*,'(a)',iostat=ios) infile
	if (ios /= 0) exit

! Open input file

	call log_string (infile)
	if (nf90_open(infile,nf90_nowrite,ncid) /= nf90_noerr) then
		call log_string ('Error: failed to open input file', .true.)
		cycle
	endif

! Check if input is GDR-C or GDR-E

	if (index(infile,'_2Pc') > 0) then
		gdre = .false.
	else if (index(infile,'_2Pe') > 0) then
		gdre = .true.
	else
		call log_string ('Error: this is neither GDR-C, nor GDR-E', .true.)
		cycle
	endif

! Read global attributes

	call nfs(nf90_inq_dimid(ncid,'time',varid))
	call nfs(nf90_inquire_dimension(ncid,varid,len=nrec))
	if (nrec == 0) then
		cycle
	else if (nrec > mrec) then
		call log_string ('Error: too many measurements', .true.)
		cycle
	endif
	call nfs(nf90_get_att(ncid,nf90_global,'mission_name',arg))
	if (arg /= 'Jason-1') then
		call log_string ('Error: wrong misson-name found in header', .true.)
		cycle
	endif

	call nfs(nf90_get_att(ncid,nf90_global,'title',arg))
	call nfs(nf90_get_att(ncid,nf90_global,'cycle_number',cyclenr))
	call nfs(nf90_get_att(ncid,nf90_global,'pass_number',passnr))
	call nfs(nf90_get_att(ncid,nf90_global,'equator_time',arg))
	equator_time = strp1985f (arg)

! Skip passes of which the cycle number or equator crossing time is outside the specified interval

	if (equator_time < times(1) .or. equator_time > times(2) .or. cyclenr < cycles(1) .or. cyclenr > cycles(2)) then
		call nfs(nf90_close(ncid))
		call log_string ('Skipped', .true.)
		cycle
	endif

! Update phase name if required

	if (cyclenr < 262) then
		phasenm = 'a'
	else if (cyclenr < 375) then
		phasenm = 'b'
	else
		phasenm = 'c'
		! Redetermine subcycle numbering
		r = (cyclenr - 500) * 280 + (passnr - 1)
		q = (r/10438) * 43
		r = modulo(r,10438)
		q = q + (r/4608) * 19
		r = modulo(r,4608)
		q = q + (r/1222) * 5
		r = modulo(r,1222)
		q = q + (r/280)
		r = modulo(r,280)
		cyclenr = q + 382
		passnr = r + 1
	endif
	if (S%phase%name /= phasenm) S%phase => rads_get_phase (S, phasenm)

! Store relevant info

	call rads_init_pass_struct (S, P)
	P%cycle = cyclenr
	P%pass = passnr
	P%equator_time = equator_time
	call nfs(nf90_get_att(ncid,nf90_global,'equator_longitude',P%equator_lon))
	call nfs(nf90_get_att(ncid,nf90_global,'first_meas_time',arg))
	P%start_time = strp1985f(arg)
	call nfs(nf90_get_att(ncid,nf90_global,'last_meas_time',arg))
	P%end_time = strp1985f(arg)

! Determine L2 processing version

	call nfs(nf90_get_att(ncid,nf90_global,'references',arg))
	i = index(infile, '/', .true.) + 1
	if (gdre) then
		P%original = trim(infile(i:))
	else
		j = index(arg, 'CMA')
		P%original = trim(infile(i:)) // ' (' // trim(arg(j:))
		cma92 = index(arg(j:), '9.2') > 0
		j = len_trim(P%original)
		P%original(j+1:) = ')'
	endif

! Allocate variables

	allocate (a(nrec),flags(nrec))
	nvar = 0

! Compile flag bits

	flags = 0
	call nc2f ('alt_state_flag_oper',0)			! bit  0: Altimeter Side A/B
	call nc2f ('qual_alt_1hz_off_nadir_angle_wf_ku',1)	! bit  1: Quality off-nadir pointing
	call nc2f ('surface_type',2,eq=2)			! bit  2: Continental ice
	call nc2f ('qual_alt_1hz_range_c',3)		! bit  3: Quality dual-frequency iono
	call nc2f ('qual_alt_1hz_range_ku',3)
	call nc2f ('surface_type',4,ge=2)			! bit  4: Water/land
	call nc2f ('surface_type',5,ge=1)			! bit  5: Ocean/other
	call nc2f ('rad_surf_type',6)				! bit  6: Radiometer land flag
	call nc2f ('ice_flag',7)					! bit  7: Ice flag
	call nc2f ('rain_flag',8)					! bit  8: Rain flag
	call nc2f ('qual_rad_1hz_tb187',9)			! bit  9: Quality 18.7 and 23.8 GHz channel
	call nc2f ('qual_rad_1hz_tb238',9)
	call nc2f ('qual_rad_1hz_tb340',10)			! bit 10: Quality 34.0 GHz channel
	call nc2f ('qual_alt_1hz_range_ku',11)		! bit 11: Quality range
	call nc2f ('qual_alt_1hz_range_c',11)
	call nc2f ('qual_inst_corr_1hz_range_ku',11)
	call nc2f ('qual_inst_corr_1hz_range_c',11)
	call nc2f ('qual_alt_1hz_swh_ku',12)		! bit 12: Quality SWH
	call nc2f ('qual_alt_1hz_swh_c',12)
	call nc2f ('qual_inst_corr_1hz_swh_ku',12)
	!call nc2f ('qual_inst_corr_1hz_swh_c',12)	! Purposely not activated. Old version had neither.
	call nc2f ('qual_alt_1hz_sig0_ku',13)		! bit 13: Quality Sigma0
	call nc2f ('qual_alt_1hz_sig0_c',13)
	call nc2f ('qual_inst_corr_1hz_sig0_ku',13)
	call nc2f ('qual_inst_corr_1hz_sig0_c',13)
	call nc2f ('orb_state_flag_rest',15,neq=3)	! bit 15: Orbital quality

! Convert all the necessary fields to RADS

	call get_var (ncid, 'time', a)
	call new_var ('time', a + sec2000)
	call cpy_var ('lat')
	call cpy_var ('lon')
	if (gdre) then
		call cpy_var ('alt', 'alt_gdre')
	else
		call cpy_var ('alt', 'alt_eiggl04s')
	endif
	call cpy_var ('orb_alt_rate', 'alt_rate')
	call cpy_var ('range_ku pseudo_dat_bias_corr ADD', 'range_ku')
	call cpy_var ('range_c pseudo_dat_bias_corr ADD', 'range_c')
	call cpy_var ('model_dry_tropo_corr', 'dry_tropo_ecmwf')
	call cpy_var ('rad_wet_tropo_corr', 'wet_tropo_rad')
	call cpy_var ('model_wet_tropo_corr', 'wet_tropo_ecmwf')
	call cpy_var ('iono_corr_alt_ku', 'iono_alt')
	call cpy_var ('iono_corr_gim_ku', 'iono_gim')
	call cpy_var ('inv_bar_corr', 'inv_bar_static')
	call cpy_var ('inv_bar_corr hf_fluctuations_corr ADD', 'inv_bar_mog2d')

	call cpy_var ('solid_earth_tide', 'tide_solid')
	if (gdre) then
		call cpy_var ('ocean_tide_sol1 load_tide_sol1 SUB', 'tide_ocean_got410')
		call cpy_var ('ocean_tide_sol2 load_tide_sol2 SUB', 'tide_ocean_got48')
		call cpy_var ('load_tide_sol1', 'tide_load_got410')
		call cpy_var ('load_tide_sol2', 'tide_load_got48')
	else
!		call cpy_var ('ocean_tide_sol1 load_tide_sol1 SUB', 'tide_ocean_got00')
!		call cpy_var ('ocean_tide_sol2 load_tide_sol2 SUB', 'tide_ocean_fes04')
!		call cpy_var ('load_tide_sol1', 'tide_load_got00')
!		call cpy_var ('load_tide_sol2', 'tide_load_fes04')
	endif
	call cpy_var ('pole_tide', 'tide_pole')
	call cpy_var ('sea_state_bias_ku', 'ssb_cls')
	call cpy_var ('sea_state_bias_c', 'ssb_cls_c')
	if (gdre) then
		call cpy_var ('geoid', 'geoid_egm2008')
		call cpy_var ('mean_sea_surface', 'mss_cnescls11')
	else
!		call cpy_var ('geoid', 'geoid_egm96')
!		call cpy_var ('mean_sea_surface', 'mss_cls01')
	endif
	call cpy_var ('swh_ku')
	call cpy_var ('swh_c')
	call cpy_var ('sig0_ku')
	call cpy_var ('sig0_c')
	call cpy_var ('wind_speed_alt')
	call cpy_var ('wind_speed_rad')
	call cpy_var ('wind_speed_model_u', 'wind_speed_ecmwf_u')
	call cpy_var ('wind_speed_model_v', 'wind_speed_ecmwf_v')
	call cpy_var ('range_rms_ku')
	call cpy_var ('range_rms_c')
	call cpy_var ('range_numval_ku')
	call cpy_var ('range_numval_c')
	call cpy_var ('bathymetry', 'topo_dtm2000')
	call cpy_var ('tb_187')
	call cpy_var ('tb_238')
	call cpy_var ('tb_340')
	a = flags
	call new_var ('flags', a)
	call cpy_var ('pseudo_dat_bias_corr', 'drange_dat')
	call cpy_var ('swh_rms_ku')
	call cpy_var ('swh_rms_c')
	call cpy_var ('sig0_rms_ku')
	call cpy_var ('sig0_rms_c')
	call cpy_var ('off_nadir_angle_wf_ku', 'off_nadir_angle2_wf_ku')
	!call cpy_var ('off_nadir_angle_pf', 'off_nadir_angle2_pf') (Always 0, so no use. Not available in GDR-E)
	if (cma92) then	! Variable name change between CMA9.2 and CMA9.3
		call cpy_var ('atmos_sig0_corr_ku', 'dsig0_atmos_ku')
		call cpy_var ('atmos_sig0_corr_c', 'dsig0_atmos_c')
	else
		call cpy_var ('atmos_corr_sig0_ku', 'dsig0_atmos_ku')
		call cpy_var ('atmos_corr_sig0_c', 'dsig0_atmos_c')
	endif
	call cpy_var ('rad_liquid_water', 'liquid_water_rad')

	! In CMA9.2 rad_water_vapor in the GDRs is in 0.01 gram/m^2 which is equivalent to 0.1 kg/m^2
	! To do the scaling right, we cannot use cpy_var.
	if (cma92) then
		call get_var (ncid, 'rad_water_vapor', a)
		call new_var ('water_vapor_rad', a*1d1)
	else
		call cpy_var ('rad_water_vapor', 'water_vapor_rad')
	endif

! Dump the data

	call nfs(nf90_close(ncid))
	call put_rads
	deallocate (a, flags)

enddo

call rads_end (S)

contains

!-----------------------------------------------------------------------
! Print synopsis
!-----------------------------------------------------------------------

subroutine synopsis (flag)
character(len=*), optional :: flag
if (rads_version ('Write Jason-1 data to RADS', flag=flag)) return
call synopsis_devel (' < list_of_JASON1_file_names')
write (*,1310)
1310 format (/ &
'This program converts Jason-1 GDR files to RADS data' / &
'files with the name $RADSDATAROOT/data/j1/a/pPPPP/j1pPPPPcCCC.nc.' / &
'The directory is created automatically and old files are overwritten.')
stop
end subroutine synopsis

end program rads_gen_j1
