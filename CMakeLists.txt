cmake_minimum_required(VERSION 3.15)

project(RenderLibs)

set(CMAKE_INSTALL_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/install CACHE PATH " " FORCE)
set(TBB_TEST OFF CACHE BOOL " " FORCE)

# TBB
add_subdirectory(oneTBB)

# Embree (depends on TBB)

# OIDN (depends on TBB, ISPC)

# OpenPGL (depends on Embree, TBB)