################################################################################
# Test utilities

include(test_util)

################################################################################
# Tests

create_standard_test(NAME cuda_lu_decomposition_mozart_in_place SOURCES test_cuda_lu_decomposition_mozart_in_place.cpp LIBRARIES musica::micm_cuda IS_CUDA_TEST)
create_standard_test(NAME cuda_linear_solver_in_place SOURCES test_cuda_linear_solver_in_place.cpp LIBRARIES musica::micm_cuda IS_CUDA_TEST)
create_standard_test(NAME cuda_rosenbrock SOURCES test_cuda_rosenbrock.cpp LIBRARIES musica::micm_cuda IS_CUDA_TEST)
create_standard_test(NAME cuda_solver_builder SOURCES test_cuda_solver_builder.cpp LIBRARIES musica::micm_cuda IS_CUDA_TEST)