cmake_minimum_required(VERSION 3.15)

project(RenderLibs)

# TBB
set(TBB_TEST OFF CACHE BOOL " " FORCE)
add_subdirectory(oneTBB)

# Embree (depends on TBB)
set(EMBREE_ISPC_SUPPORT           OFF CACHE BOOL " " FORCE)
set(EMBREE_IGNORE_CMAKE_CXX_FLAGS OFF CACHE BOOL " " FORCE)

# Disable all unused features to shorten build times
set(EMBREE_TUTORIALS              OFF CACHE BOOL " " FORCE)
set(EMBREE_FILTER_FUNCTION        OFF CACHE BOOL " " FORCE)
set(EMBREE_GEOMETRY_QUAD          OFF CACHE BOOL " " FORCE)
set(EMBREE_GEOMETRY_CURVE         OFF CACHE BOOL " " FORCE)
set(EMBREE_GEOMETRY_GRID          OFF CACHE BOOL " " FORCE)
set(EMBREE_GEOMETRY_SUBDIVISION   OFF CACHE BOOL " " FORCE)
set(EMBREE_GEOMETRY_INSTANCE      OFF CACHE BOOL " " FORCE)
set(EMBREE_GEOMETRY_USER          ON  CACHE BOOL " " FORCE)

# We don't bother compiling and linking TBB
set(EMBREE_TASKING_SYSTEM         "TBB" CACHE STRING " " FORCE)

# Enable only AVX and AVX2 for faster github actions deployment
set(EMBREE_MAX_ISA                "NONE" CACHE STRING " " FORCE)
set(EMBREE_ISA_AVX2               ON  CACHE BOOL " " FORCE)
set(EMBREE_ISA_SSE2               OFF CACHE BOOL " " FORCE)
set(EMBREE_ISA_SSE42              OFF CACHE BOOL " " FORCE)
set(EMBREE_ISA_AVX512             OFF CACHE BOOL " " FORCE)
set(EMBREE_ISA_AVX                ON  CACHE BOOL " " FORCE)
set(EMBREE_ISA_NEON               ON  CACHE BOOL " " FORCE)

# add_subdirectory(embree)

# OIDN (depends on TBB, ISPC)
add_subdirectory(oidn)

# OpenPGL (depends on Embree, TBB)