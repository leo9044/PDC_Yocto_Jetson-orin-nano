cmake_minimum_required(VERSION 3.16)

project(UnifiedCompositor VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Qt packages - GUI + WaylandCompositor
find_package(Qt5 REQUIRED COMPONENTS Core Quick Qml WaylandCompositor)

# CommonAPI & vsomeip
find_package(CommonAPI 3.2 REQUIRED)
find_package(CommonAPI-SomeIP 3.2 REQUIRED)
find_package(vsomeip3 3.5 REQUIRED)

# CommonAPI generated code path (set by Yocto via EXTRA_OECMAKE)
if(NOT COMMONAPI_GEN_DIR)
    if(DEFINED ENV{COMMONAPI_GEN_DIR})
        set(COMMONAPI_GEN_DIR $ENV{COMMONAPI_GEN_DIR})
    else()
        set(COMMONAPI_GEN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../commonapi/generated")
    endif()
endif()

# RPATH for vsomeip/CommonAPI libraries
if(DEFINED ENV{DEPLOY_PREFIX})
    set(INSTALL_PREFIX $ENV{DEPLOY_PREFIX})
else()
    set(INSTALL_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/../../install_folder")
endif()
set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH};${INSTALL_PREFIX}")
set(CMAKE_INSTALL_RPATH "${INSTALL_PREFIX}/lib")
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)

message(STATUS "CommonAPI generated code: ${COMMONAPI_GEN_DIR}")

include_directories(
    ${COMMONAPI_GEN_DIR}/core
    ${COMMONAPI_GEN_DIR}/someip
)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(SOURCES
    src/main_compositor.cpp
    src/VehicleControlClient.cpp
)

set(HEADERS
    src/VehicleControlClient.h
)

# CommonAPI generated SomeIP binding for VehicleControl
set(COMMONAPI_SOURCES
    ${COMMONAPI_GEN_DIR}/someip/v1/vehiclecontrol/VehicleControlSomeIPProxy.cpp
    ${COMMONAPI_GEN_DIR}/someip/v1/vehiclecontrol/VehicleControlSomeIPDeployment.cpp
)

set(QML_RESOURCES
    qml_compositor.qrc
)

add_executable(UnifiedCompositor
    ${SOURCES}
    ${HEADERS}
    ${COMMONAPI_SOURCES}
    ${QML_RESOURCES}
)

target_link_libraries(UnifiedCompositor
    Qt5::Core
    Qt5::Quick
    Qt5::Qml
    Qt5::WaylandCompositor
    CommonAPI
    CommonAPI-SomeIP
    vsomeip3
)

install(TARGETS UnifiedCompositor DESTINATION bin)
