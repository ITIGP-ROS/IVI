cmake_minimum_required(VERSION 3.16)

project(IVI VERSION 1.0 LANGUAGES CXX)

set(CMAKE_AUTORCC ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick Quick3D Location Positioning DBus Concurrent Multimedia)
find_package(PkgConfig REQUIRED)
pkg_check_modules(PULSE REQUIRED libpulse)

# --- DriveView (3D surroundings visualization) ---
find_package(rclcpp REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(std_msgs REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(object_detection_msgs REQUIRED)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(appIVI
    main.cpp
    Backend/BluetoothManager.cpp
    Backend/USBManager.cpp
    Backend/BluetoothHWManager.cpp
    Backend/BlueZ.cpp
    Backend/BluetoothAgent.cpp
    Backend/WifiManager.cpp
    Backend/WifiCredSender.cpp
    Backend/SystemVolumeController.cpp
    Backend/SpeechManager.cpp
    Backend/MediaLibrary.cpp
    Backend/AmbientLightManager.cpp
    DriveView/src/ros_node.cpp
    DriveView/src/detection_model.cpp
    DriveView/src/detection_instancing.cpp
    DriveView/src/car_info.cpp
    DriveView/src/box_transform.cpp
    DriveView/inc/ros_node.h
    DriveView/inc/detection_model.h
    DriveView/inc/detection_instancing.h
    DriveView/inc/car_info.h
    DriveView/inc/box_transform.h
    DriveView/inc/detection_data.h
)

target_include_directories(appIVI PRIVATE ${PULSE_INCLUDE_DIRS})
target_include_directories(appIVI PRIVATE DriveView)

# Bench switch for the ambient light CAN link. ON prints the frames to the
# terminal instead of opening can0, for developing on a laptop with no bus:
#   cmake -B build -DAMBIENT_CAN_SIMULATE=ON
option(AMBIENT_CAN_SIMULATE "Print ambient-light CAN frames instead of sending them" OFF)
# Defined either way, so the flag works in both directions. Defining it only
# when ON meant a build could never turn simulation back off — whatever the
# source happened to default to won, and a head unit could ship printing frames
# to its log while driving nothing.
target_compile_definitions(appIVI PRIVATE
    AMBIENT_CAN_SIMULATE=$<IF:$<BOOL:${AMBIENT_CAN_SIMULATE}>,1,0>)

qt_add_qml_module(appIVI
    URI IVI
    VERSION 1.0
    QML_FILES
        Main.qml
        pages/WeatherPage.qml
        pages/MediaPlayerPage.qml
        pages/SettingPage.qml
        API/WeatherAPI.qml
        API/RadioAPI.qml
        Components/WindowBar.qml
        Components/MediaCard.qml
        Components/CarInfoPopup.qml
        Components/AmbientCard.qml
        Components/VirtualKeyboard.qml
        MediaPages/AudioPage.qml
        MediaPages/VideoPage.qml
        MediaPages/RadioPage.qml
        SettingPages/BluetoothPage.qml
        SettingPages/WiFiPage.qml
        SettingPages/AmbientLightPage.qml
        DriveView/DriveViewPage.qml
        DriveView/qml/Scene3D.qml
        DriveView/qml/MiniScene3D.qml
        DriveView/qml/GroundPlane.qml
        DriveView/qml/MapOSM.qml
        DriveView/models_3d/audi_low_poly/Audi_rs7_free__low_poly.qml
    RESOURCES
        resources.qrc
        DriveView/res.qrc
)

set_target_properties(appIVI PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appIVI PRIVATE
    Qt6::Quick
    Qt6::Quick3D
    Qt6::Location
    Qt6::Positioning
    Qt6::DBus
    Qt6::Concurrent
    Qt6::Multimedia
    ${PULSE_LIBRARIES}
    vosk
    rclcpp::rclcpp
    sensor_msgs::sensor_msgs
    geometry_msgs::geometry_msgs
    std_msgs::std_msgs
    object_detection_msgs::object_detection_msgs
)

include(GNUInstallDirs)
install(TARGETS appIVI
    BUNDLE  DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)