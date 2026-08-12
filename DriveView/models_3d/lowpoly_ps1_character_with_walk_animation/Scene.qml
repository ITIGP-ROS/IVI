import QtQuick
import QtQuick3D

import QtQuick.Timeline

Node {
    id: node

    // Resources
    PrincipledMaterial {
        id: scene___Root_material
        objectName: "Scene_-_Root"
        baseColor: "#ff5987c9"
        roughness: 0.6000000238418579
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    Skin {
        id: skin
        joints: [
            _rootJoint,
            root_01,
            spine_02,
            spine_001_03,
            spine_002_04,
            spine_003_05,
            neck_06,
            head_07,
            head_end_033,
            collar_L_08,
            upper_arm_L_09,
            lower_arm_L_010,
            hand_L_011,
            hand_L_end_034,
            collar_R_012,
            upper_arm_R_013,
            lower_arm_R_014,
            hand_R_015,
            hand_R_end_035,
            pelvis_L_00,
            thigh_L_016,
            shin_L_017,
            foot_L_018,
            toe_L_019,
            toe_L_end_036,
            pelvis_R_020,
            thigh_R_021,
            shin_R_022,
            foot_R_023,
            toe_R_024,
            toe_R_end_037,
            hand_IK_L_025,
            hand_IK_L_end_038,
            arm_pole_L_026,
            arm_pole_L_end_039,
            hand_IK_R_027,
            hand_IK_R_end_040,
            arm_pole_R_028,
            arm_pole_R_end_041,
            ik_Foor_L_029,
            pole_L_030,
            pole_L_end_042,
            ik_Foor_R_031,
            pole_R_032,
            pole_R_end_043
        ]
        inverseBindPoses: [
            Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(1, 3.35924e-08, -2.3604e-07, -3.35014e-08, 1.2056e-15, 0.990024, 0.140897, -0.958665, 2.38419e-07, -0.140897, 0.990024, 0.140515, 0, 0, 0, 1),
            Qt.matrix4x4(1, -3.28803e-08, -2.3614e-07, 3.93979e-08, 2.60513e-14, 0.990445, -0.13791, -1.08423, 2.38419e-07, 0.13791, 0.990445, -0.165247, 0, 0, 0, 1),
            Qt.matrix4x4(1, -6.85091e-08, -2.28364e-07, 8.42196e-08, 2.29213e-14, 0.957826, -0.287348, -1.2056, 2.38419e-07, 0.287348, 0.957826, -0.353242, 0, 0, 0, 1),
            Qt.matrix4x4(1, 3.66753e-09, -2.3839e-07, -1.56472e-08, 1.61903e-14, 0.999882, 0.0153828, -1.37662, 2.38419e-07, -0.0153828, 0.999882, 0.065629, 0, 0, 0, 1),
            Qt.matrix4x4(1, 4.30706e-08, -2.34496e-07, -7.49327e-08, 3.17348e-14, 0.983547, 0.180651, -1.4763, 2.38419e-07, -0.180651, 0.983547, 0.314291, 0, 0, 0, 1),
            Qt.matrix4x4(1, 2.13713e-08, -2.37459e-07, -4.01169e-08, 9.70379e-15, 0.995975, 0.0896377, -1.59913, 2.38419e-07, -0.0896377, 0.995974, 0.168262, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(-0.0108, -0.999941, -0.00112855, 1.47687, 0.996497, -0.0108563, 0.0829173, 0.0101318, -0.0829247, -0.000229089, 0.996556, -0.00928169, 0, 0, 0, 1),
            Qt.matrix4x4(0.0216137, -0.999766, 0.00101694, 1.46877, 0.992427, 0.0215781, 0.120926, -0.156084, -0.120919, -0.00160441, 0.992661, 0.0740415, 0, 0, 0, 1),
            Qt.matrix4x4(0.0125606, -0.999921, -0.000140043, 1.47269, 0.913603, 0.0114194, 0.406446, -0.382754, -0.406412, -0.00523316, 0.913675, 0.194805, 0, 0, 0, 1),
            Qt.matrix4x4(-0.161087, -0.986883, 0.0105921, 1.57501, 0.93603, -0.149367, 0.318648, -0.475772, -0.312886, 0.0612447, 0.947814, 0.0264024, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(-0.0108001, 0.999941, 0.00112854, -1.47687, -0.996497, -0.0108565, 0.0829173, 0.010132, 0.0829246, -0.00022907, 0.996556, -0.00928172, 0, 0, 0, 1),
            Qt.matrix4x4(0.0216136, 0.999766, -0.00101694, -1.46877, -0.992427, 0.0215779, 0.120926, -0.156084, 0.120919, -0.00160439, 0.992661, 0.0740415, 0, 0, 0, 1),
            Qt.matrix4x4(0.0125605, 0.999921, 0.000140043, -1.47269, -0.913603, 0.0114193, 0.406446, -0.382754, 0.406412, -0.0052331, 0.913675, 0.194804, 0, 0, 0, 1),
            Qt.matrix4x4(-0.161088, 0.986883, -0.0105921, -1.57501, -0.93603, -0.149367, 0.318648, -0.475772, 0.312886, 0.0612447, 0.947814, 0.0264022, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(3.42447e-07, -2.1684e-23, 1, 0.00404042, 0.824638, 0.565661, -2.82395e-07, -0.548069, -0.565661, 0.824638, 1.93709e-07, -0.798991, 0, 0, 0, 1),
            Qt.matrix4x4(0.996524, -0.0832778, -0.00210912, -0.0195614, -0.0832864, -0.996516, -0.00442055, 0.979141, -0.00173364, 0.00458085, -0.999988, -0.0180135, 0, 0, 0, 1),
            Qt.matrix4x4(0.998785, -0.049142, -0.00366399, -0.0369359, -0.0492654, -0.994053, -0.0971169, 0.502683, 0.00113031, 0.0971794, -0.995266, -0.0648015, 0, 0, 0, 1),
            Qt.matrix4x4(0.987393, 0.0835856, -0.134416, -0.0545237, 0.158285, -0.521416, 0.838493, 0.0830858, -6.70094e-07, -0.849198, -0.528073, 0.0373066, 0, 0, 0, 1),
            Qt.matrix4x4(1, -4.54037e-07, -2.46397e-08, -0.0589233, 1.23407e-09, -0.0514782, 0.998674, -0.038264, -4.54703e-07, -0.998674, -0.0514782, 0.0214794, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(2.54148e-07, 2.1684e-23, -1, -0.00404042, -0.824638, 0.565661, -2.0958e-07, -0.548069, 0.565661, 0.824638, 1.43762e-07, -0.798991, 0, 0, 0, 1),
            Qt.matrix4x4(0.996524, 0.0832779, 0.00210914, 0.0195612, 0.0832866, -0.996516, -0.00442051, 0.979142, 0.00173366, 0.00458081, -0.999988, -0.0180134, 0, 0, 0, 1),
            Qt.matrix4x4(0.998785, 0.0491422, 0.00366388, 0.0369358, 0.0492656, -0.994053, -0.0971169, 0.502683, -0.00113044, 0.0971794, -0.995266, -0.0648015, 0, 0, 0, 1),
            Qt.matrix4x4(0.987394, -0.0835854, 0.134416, 0.0545237, -0.158285, -0.521416, 0.838493, 0.0830859, 7.55396e-07, -0.849199, -0.528073, 0.0373069, 0, 0, 0, 1),
            Qt.matrix4x4(1, 6.67572e-07, -4.3176e-08, 0.0589233, 7.74839e-08, -0.0514777, 0.998674, -0.0382641, 6.64464e-07, -0.998674, -0.0514777, 0.0214795, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1),
            Qt.matrix4x4(100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1)
        ]
    }

    // Nodes:
    Node {
        id: sketchfab_model
        objectName: "Sketchfab_model"
        rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
        Node {
            id: node013e06140dd3460a9caec1f81f29ef59_fbx
            objectName: "013e06140dd3460a9caec1f81f29ef59.fbx"
            rotation: Qt.quaternion(0.707107, 0.707107, 0, 0)
            scale: Qt.vector3d(0.01, 0.01, 0.01)
            Node {
                id: object_2
                objectName: "Object_2"
                Node {
                    id: rootNode
                    objectName: "RootNode"
                    Node {
                        id: plane
                        objectName: "Plane"
                        rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                        scale: Qt.vector3d(100, 100, 100)
                    }
                    Node {
                        id: armature
                        objectName: "Armature"
                        rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                        scale: Qt.vector3d(100, 100, 100)
                        Node {
                            id: object_6
                            objectName: "Object_6"
                            Node {
                                id: _rootJoint
                                objectName: "_rootJoint"
                                Node {
                                    id: root_01
                                    objectName: "root_01"
                                    rotation: Qt.quaternion(1, -1.32349e-23, 0, 0)
                                    Node {
                                        id: spine_02
                                        objectName: "spine_02"
                                        position: Qt.vector3d(0.0167583, 0.024633, 0.87004)
                                        rotation: Qt.quaternion(0.655402, 0.75528, 7.813e-08, 9.00365e-08)
                                        Node {
                                            id: spine_001_03
                                            objectName: "spine.001_03"
                                            position: Qt.vector3d(-3.4911e-10, 0.129045, 1.47057e-08)
                                            rotation: Qt.quaternion(0.992864, -0.0993626, 0.0640493, -0.0156613)
                                            scale: Qt.vector3d(1, 1, 1)
                                            Node {
                                                id: spine_002_04
                                                objectName: "spine.002_04"
                                                position: Qt.vector3d(-2.56114e-09, 0.161138, -2.32831e-09)
                                                rotation: Qt.quaternion(0.996933, -0.0653838, -0.0136889, 0.0407716)
                                                scale: Qt.vector3d(1, 1, 1)
                                                Node {
                                                    id: spine_003_05
                                                    objectName: "spine.003_05"
                                                    position: Qt.vector3d(-4.65661e-10, 0.126551, 9.0804e-09)
                                                    rotation: Qt.quaternion(0.987906, 0.151428, 0.00542765, -0.0329025)
                                                    scale: Qt.vector3d(1, 1, 1)
                                                    Node {
                                                        id: neck_06
                                                        objectName: "neck_06"
                                                        position: Qt.vector3d(-4.65661e-09, 0.13133, 2.80561e-08)
                                                        rotation: Qt.quaternion(0.996547, 0.083037, 3.65059e-10, 2.07937e-08)
                                                        scale: Qt.vector3d(1, 1, 1)
                                                        Node {
                                                            id: head_07
                                                            objectName: "head_07"
                                                            position: Qt.vector3d(-3.14321e-09, 0.100647, -1.61817e-08)
                                                            rotation: Qt.quaternion(0.996618, -0.0447275, -0.0674682, 0.0141642)
                                                            scale: Qt.vector3d(1, 1, 1)
                                                            Node {
                                                                id: head_end_033
                                                                objectName: "head_end_033"
                                                                position: Qt.vector3d(3.46945e-18, 0.202839, 0)
                                                                rotation: Qt.quaternion(1, 0, 0, 1.51788e-18)
                                                            }
                                                        }
                                                    }
                                                    Node {
                                                        id: collar_L_08
                                                        objectName: "collar.L_08"
                                                        position: Qt.vector3d(0.00508413, 0.100251, 0.0529854)
                                                        rotation: Qt.quaternion(0.649945, 0.0311321, -0.0457168, -0.757966)
                                                        scale: Qt.vector3d(1, 1, 1)
                                                        Node {
                                                            id: upper_arm_L_09
                                                            objectName: "upper_arm.L_09"
                                                            position: Qt.vector3d(0.00368242, 0.121146, -0.0764979)
                                                            rotation: Qt.quaternion(0.82754, -0.00187408, 0.245692, -0.504787)
                                                            scale: Qt.vector3d(1, 1, 1)
                                                            Node {
                                                                id: lower_arm_L_010
                                                                objectName: "lower_arm.L_010"
                                                                position: Qt.vector3d(-4.84288e-08, 0.280372, 7.45058e-09)
                                                                rotation: Qt.quaternion(0.964484, 0.264016, -0.000633439, -0.0080524)
                                                                scale: Qt.vector3d(1, 1, 1)
                                                                Node {
                                                                    id: hand_L_011
                                                                    objectName: "hand.L_011"
                                                                    position: Qt.vector3d(1.86265e-08, 0.325037, 0)
                                                                    rotation: Qt.quaternion(0.993913, -0.0603847, -0.0393615, -0.083313)
                                                                    scale: Qt.vector3d(1, 1, 1)
                                                                    Node {
                                                                        id: hand_L_end_034
                                                                        objectName: "hand.L_end_034"
                                                                        position: Qt.vector3d(0, 0.117407, 2.77556e-17)
                                                                        rotation: Qt.quaternion(1, -6.93889e-18, 8.32667e-17, 8.67362e-19)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                    Node {
                                                        id: collar_R_012
                                                        objectName: "collar.R_012"
                                                        position: Qt.vector3d(-0.00508417, 0.100251, 0.0529854)
                                                        rotation: Qt.quaternion(0.649945, 0.031132, 0.0457167, 0.757966)
                                                        scale: Qt.vector3d(1, 1, 1)
                                                        Node {
                                                            id: upper_arm_R_013
                                                            objectName: "upper_arm.R_013"
                                                            position: Qt.vector3d(-0.00368243, 0.121146, -0.0764979)
                                                            rotation: Qt.quaternion(0.834387, -0.0938416, -0.143177, 0.52392)
                                                            scale: Qt.vector3d(1, 1, 1)
                                                            Node {
                                                                id: lower_arm_R_014
                                                                objectName: "lower_arm.R_014"
                                                                position: Qt.vector3d(2.79397e-07, 0.280372, 6.70552e-08)
                                                                rotation: Qt.quaternion(0.768895, 0.639077, 0.00050498, 0.0194916)
                                                                scale: Qt.vector3d(1, 1, 1)
                                                                Node {
                                                                    id: hand_R_015
                                                                    objectName: "hand.R_015"
                                                                    position: Qt.vector3d(2.23517e-08, 0.325036, -4.47035e-08)
                                                                    rotation: Qt.quaternion(0.998281, 0.0307638, 0.0322609, 0.0380447)
                                                                    scale: Qt.vector3d(1, 1, 1)
                                                                    Node {
                                                                        id: hand_R_end_035
                                                                        objectName: "hand.R_end_035"
                                                                        position: Qt.vector3d(5.55112e-17, 0.117407, 1.11022e-16)
                                                                        rotation: Qt.quaternion(1, -5.55112e-17, -1.54074e-33, 2.77556e-17)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Node {
                                            id: pelvis_L_00
                                            objectName: "pelvis.L_00"
                                            position: Qt.vector3d(-3.49107e-10, -2.32831e-09, 9.58343e-09)
                                            rotation: Qt.quaternion(0.600797, -0.372884, -0.647342, -0.284514)
                                            scale: Qt.vector3d(1, 1, 1)
                                            Node {
                                                id: thigh_L_016
                                                objectName: "thigh.L_016"
                                                position: Qt.vector3d(-0.00968577, 0.0862867, -0.0527808)
                                                rotation: Qt.quaternion(-0.132697, 0.696773, 0.467478, -0.527602)
                                                scale: Qt.vector3d(1, 1, 1)
                                                Node {
                                                    id: shin_L_017
                                                    objectName: "shin.L_017"
                                                    position: Qt.vector3d(1.86265e-09, 0.471651, 3.32948e-08)
                                                    rotation: Qt.quaternion(0.897656, 0.440364, -0.00829858, -0.0149777)
                                                    scale: Qt.vector3d(1, 0.999999, 1)
                                                    Node {
                                                        id: foot_L_018
                                                        objectName: "foot.L_018"
                                                        position: Qt.vector3d(-2.91038e-10, 0.427155, -3.36149e-09)
                                                        rotation: Qt.quaternion(0.767828, -0.629602, -0.0718229, -0.0942471)
                                                        scale: Qt.vector3d(1, 1, 1)
                                                        Node {
                                                            id: toe_L_019
                                                            objectName: "toe.L_019"
                                                            position: Qt.vector3d(2.21189e-09, 0.115223, -3.0268e-09)
                                                            rotation: Qt.quaternion(0.95226, -0.294478, -0.0270015, 0.0758627)
                                                            scale: Qt.vector3d(1, 1, 1)
                                                            Node {
                                                                id: toe_L_end_036
                                                                objectName: "toe.L_end_036"
                                                                position: Qt.vector3d(0, 0.0788573, 0)
                                                                rotation: Qt.quaternion(1, 0, 9.75782e-19, 0)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Node {
                                            id: pelvis_R_020
                                            objectName: "pelvis.R_020"
                                            position: Qt.vector3d(-3.49107e-10, -2.32831e-09, 9.58343e-09)
                                            rotation: Qt.quaternion(0.600797, -0.372884, 0.647342, 0.284514)
                                            Node {
                                                id: thigh_R_021
                                                objectName: "thigh.R_021"
                                                position: Qt.vector3d(0.00968577, 0.0862867, -0.0527808)
                                                rotation: Qt.quaternion(-0.308751, 0.627318, -0.358876, 0.618346)
                                                scale: Qt.vector3d(1, 1, 1)
                                                Node {
                                                    id: shin_R_022
                                                    objectName: "shin.R_022"
                                                    position: Qt.vector3d(-2.90311e-09, 0.471651, -2.32831e-09)
                                                    rotation: Qt.quaternion(0.859237, 0.511292, 0.00947886, 0.01426)
                                                    scale: Qt.vector3d(1, 1, 0.999999)
                                                    Node {
                                                        id: foot_R_023
                                                        objectName: "foot.R_023"
                                                        position: Qt.vector3d(9.31323e-10, 0.427156, 3.25963e-09)
                                                        rotation: Qt.quaternion(0.87649, -0.470351, 0.10202, -0.0113092)
                                                        scale: Qt.vector3d(1, 1, 1)
                                                        Node {
                                                            id: toe_R_024
                                                            objectName: "toe.R_024"
                                                            position: Qt.vector3d(4.19095e-09, 0.115224, 2.03581e-08)
                                                            rotation: Qt.quaternion(0.861852, -0.498292, 0.0406368, -0.0852352)
                                                            scale: Qt.vector3d(1, 1, 1)
                                                            Node {
                                                                id: toe_R_end_037
                                                                objectName: "toe.R_end_037"
                                                                position: Qt.vector3d(0, 0.0788573, 1.38778e-17)
                                                                rotation: Qt.quaternion(1, -9.62965e-35, -6.93889e-18, -1.38778e-17)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Node {
                                            id: hand_IK_L_025
                                            objectName: "hand_IK.L_025"
                                            position: Qt.vector3d(0.258514, -0.088257, -0.0667899)
                                            rotation: Qt.quaternion(-0.462788, 0.533314, -0.46409, 0.534813)
                                            scale: Qt.vector3d(1, 1, 1)
                                            Node {
                                                id: hand_IK_L_end_038
                                                objectName: "hand_IK.L_end_038"
                                                position: Qt.vector3d(1.11022e-16, 0.0952281, 0)
                                                rotation: Qt.quaternion(1, 1.05879e-22, -1.67176e-19, 5.29396e-23)
                                            }
                                        }
                                        Node {
                                            id: arm_pole_L_026
                                            objectName: "arm_pole.L_026"
                                            position: Qt.vector3d(0.410359, 0.410168, -0.730937)
                                            rotation: Qt.quaternion(-0.468684, 0.540108, -0.458134, 0.527951)
                                            scale: Qt.vector3d(1, 1, 1)
                                            Node {
                                                id: arm_pole_L_end_039
                                                objectName: "arm_pole.L_end_039"
                                                position: Qt.vector3d(-2.22045e-16, 0.12197, 0)
                                                rotation: Qt.quaternion(1, -3.23644e-41, -1.22267e-18, -2.64698e-23)
                                            }
                                        }
                                        Node {
                                            id: hand_IK_R_027
                                            objectName: "hand_IK.R_027"
                                            position: Qt.vector3d(-0.176399, 0.0820623, 0.162157)
                                            rotation: Qt.quaternion(0.462788, -0.533314, -0.46409, 0.534813)
                                            scale: Qt.vector3d(1, 1, 1)
                                            Node {
                                                id: hand_IK_R_end_040
                                                objectName: "hand_IK.R_end_040"
                                                position: Qt.vector3d(1.11022e-16, 0.0952281, 2.77556e-17)
                                                rotation: Qt.quaternion(1, -4.68874e-42, -8.85702e-20, -5.29396e-23)
                                            }
                                        }
                                        Node {
                                            id: arm_pole_R_028
                                            objectName: "arm_pole.R_028"
                                            position: Qt.vector3d(-0.410358, 0.410168, -0.730937)
                                            rotation: Qt.quaternion(-0.468684, 0.540108, 0.458135, -0.527951)
                                            scale: Qt.vector3d(1, 1, 1)
                                            Node {
                                                id: arm_pole_R_end_041
                                                objectName: "arm_pole.R_end_041"
                                                position: Qt.vector3d(0, 0.12197, 5.55112e-17)
                                                rotation: Qt.quaternion(1, 2.64698e-23, -2.37755e-18, 2.64698e-23)
                                            }
                                        }
                                    }
                                    Node {
                                        id: ik_Foor_L_029
                                        objectName: "IK.Foor.L_029"
                                        position: Qt.vector3d(0.0804206, -0.0503006, 0.0735765)
                                        rotation: Qt.quaternion(0.999737, -1.32453e-23, 0.0229172, 3.03625e-25)
                                        Node {
                                            id: pole_L_030
                                            objectName: "pole.L_030"
                                            position: Qt.vector3d(0.00156508, -1.24931, 0.425133)
                                            rotation: Qt.quaternion(-4.37028e-08, 0.999803, -8.66623e-10, -0.019826)
                                            scale: Qt.vector3d(1, 1, 1)
                                            Node {
                                                id: pole_L_end_042
                                                objectName: "pole.L_end_042"
                                                position: Qt.vector3d(-1.38778e-17, 0.163638, 1.11022e-16)
                                                rotation: Qt.quaternion(1, -6.61744e-24, -7.53189e-18, -8.27181e-25)
                                            }
                                        }
                                    }
                                    Node {
                                        id: ik_Foor_R_031
                                        objectName: "IK.Foor.R_031"
                                        position: Qt.vector3d(-0.0928261, 0.362688, 0.175996)
                                        rotation: Qt.quaternion(0.999737, -1.32453e-23, -0.0229172, -3.03625e-25)
                                        Node {
                                            id: pole_R_032
                                            objectName: "pole.R_032"
                                            position: Qt.vector3d(-0.00156508, -1.24931, 0.425133)
                                            rotation: Qt.quaternion(-4.37028e-08, 0.999803, 8.66623e-10, 0.019826)
                                            scale: Qt.vector3d(1, 1, 1)
                                            Node {
                                                id: pole_R_end_043
                                                objectName: "pole.R_end_043"
                                                position: Qt.vector3d(0, 0.163638, -1.11022e-16)
                                                rotation: Qt.quaternion(1, -6.61744e-24, 7.53189e-18, 8.27181e-25)
                                            }
                                        }
                                    }
                                }
                            }
                            Model {
                                id: object_9
                                objectName: "Object_9"
                                source: "meshes/plane__0_mesh.mesh"
                                skin: skin
                                materials: [
                                    scene___Root_material
                                ]
                            }
                            Node {
                                id: object_8
                                objectName: "Object_8"
                                rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
                                scale: Qt.vector3d(100, 100, 100)
                            }
                        }
                    }
                }
            }
        }
    }

    // Animations:
    Timeline {
        id: armature_walk1_timeline
        objectName: "Armature|walk1"
        property real framesPerSecond: 1000
        startFrame: 0
        endFrame: 1280
        currentFrame: 0
        enabled: true
        animations: TimelineAnimation {
            duration: 1280
            from: 0
            to: 1280
            running: true
            loops: Animation.Infinite
        }
        KeyframeGroup {
            target: hand_IK_L_025
            property: "position"
            keyframeSource: "animations/hand_IK_L_025_position_0.qad"
        }
        KeyframeGroup {
            target: pelvis_R_020
            property: "position"
            keyframeSource: "animations/pelvis_R_020_position_0.qad"
        }
        KeyframeGroup {
            target: thigh_R_021
            property: "rotation"
            keyframeSource: "animations/thigh_R_021_rotation_0.qad"
        }
        KeyframeGroup {
            target: shin_R_022
            property: "rotation"
            keyframeSource: "animations/shin_R_022_rotation_0.qad"
        }
        KeyframeGroup {
            target: foot_R_023
            property: "rotation"
            keyframeSource: "animations/foot_R_023_rotation_0.qad"
        }
        KeyframeGroup {
            target: toe_R_024
            property: "position"
            keyframeSource: "animations/toe_R_024_position_0.qad"
        }
        KeyframeGroup {
            target: toe_R_024
            property: "rotation"
            keyframeSource: "animations/toe_R_024_rotation_0.qad"
        }
        KeyframeGroup {
            target: pelvis_L_00
            property: "position"
            keyframeSource: "animations/pelvis_L_00_position_0.qad"
        }
        KeyframeGroup {
            target: thigh_L_016
            property: "rotation"
            keyframeSource: "animations/thigh_L_016_rotation_0.qad"
        }
        KeyframeGroup {
            target: shin_L_017
            property: "position"
            Keyframe {
                frame: 0
                value: Qt.vector3d(6.51926e-09, 0.471651, 2.67755e-09)
            }
        }
        KeyframeGroup {
            target: shin_L_017
            property: "rotation"
            keyframeSource: "animations/shin_L_017_rotation_0.qad"
        }
        KeyframeGroup {
            target: foot_L_018
            property: "rotation"
            keyframeSource: "animations/foot_L_018_rotation_0.qad"
        }
        KeyframeGroup {
            target: toe_L_019
            property: "position"
            keyframeSource: "animations/toe_L_019_position_0.qad"
        }
        KeyframeGroup {
            target: toe_L_019
            property: "rotation"
            keyframeSource: "animations/toe_L_019_rotation_0.qad"
        }
        KeyframeGroup {
            target: head_07
            property: "position"
            keyframeSource: "animations/head_07_position_0.qad"
        }
        KeyframeGroup {
            target: head_07
            property: "rotation"
            keyframeSource: "animations/head_07_rotation_0.qad"
        }
        KeyframeGroup {
            target: spine_002_04
            property: "position"
            keyframeSource: "animations/spine_002_04_position_0.qad"
        }
        KeyframeGroup {
            target: spine_002_04
            property: "rotation"
            keyframeSource: "animations/spine_002_04_rotation_0.qad"
        }
        KeyframeGroup {
            target: neck_06
            property: "position"
            keyframeSource: "animations/neck_06_position_0.qad"
        }
        KeyframeGroup {
            target: neck_06
            property: "rotation"
            keyframeSource: "animations/neck_06_rotation_0.qad"
        }
        KeyframeGroup {
            target: spine_001_03
            property: "position"
            keyframeSource: "animations/spine_001_03_position_0.qad"
        }
        KeyframeGroup {
            target: spine_001_03
            property: "rotation"
            keyframeSource: "animations/spine_001_03_rotation_0.qad"
        }
        KeyframeGroup {
            target: hand_IK_R_027
            property: "position"
            keyframeSource: "animations/hand_IK_R_027_position_0.qad"
        }
        KeyframeGroup {
            target: hand_L_011
            property: "position"
            keyframeSource: "animations/hand_L_011_position_0.qad"
        }
        KeyframeGroup {
            target: hand_L_011
            property: "rotation"
            keyframeSource: "animations/hand_L_011_rotation_0.qad"
        }
        KeyframeGroup {
            target: lower_arm_L_010
            property: "position"
            keyframeSource: "animations/lower_arm_L_010_position_0.qad"
        }
        KeyframeGroup {
            target: lower_arm_L_010
            property: "rotation"
            keyframeSource: "animations/lower_arm_L_010_rotation_0.qad"
        }
        KeyframeGroup {
            target: upper_arm_L_09
            property: "position"
            keyframeSource: "animations/upper_arm_L_09_position_0.qad"
        }
        KeyframeGroup {
            target: upper_arm_L_09
            property: "rotation"
            keyframeSource: "animations/upper_arm_L_09_rotation_0.qad"
        }
        KeyframeGroup {
            target: spine_02
            property: "position"
            keyframeSource: "animations/spine_02_position_0.qad"
        }
        KeyframeGroup {
            target: collar_L_08
            property: "rotation"
            keyframeSource: "animations/collar_L_08_rotation_0.qad"
        }
        KeyframeGroup {
            target: hand_R_015
            property: "position"
            keyframeSource: "animations/hand_R_015_position_0.qad"
        }
        KeyframeGroup {
            target: hand_R_015
            property: "rotation"
            keyframeSource: "animations/hand_R_015_rotation_0.qad"
        }
        KeyframeGroup {
            target: ik_Foor_L_029
            property: "position"
            keyframeSource: "animations/ik_Foor_L_029_position_0.qad"
        }
        KeyframeGroup {
            target: lower_arm_R_014
            property: "position"
            keyframeSource: "animations/lower_arm_R_014_position_0.qad"
        }
        KeyframeGroup {
            target: lower_arm_R_014
            property: "rotation"
            keyframeSource: "animations/lower_arm_R_014_rotation_0.qad"
        }
        KeyframeGroup {
            target: upper_arm_R_013
            property: "position"
            Keyframe {
                frame: 0
                value: Qt.vector3d(-0.00368272, 0.121146, -0.0764979)
            }
        }
        KeyframeGroup {
            target: upper_arm_R_013
            property: "rotation"
            keyframeSource: "animations/upper_arm_R_013_rotation_0.qad"
        }
        KeyframeGroup {
            target: collar_R_012
            property: "rotation"
            keyframeSource: "animations/collar_R_012_rotation_0.qad"
        }
        KeyframeGroup {
            target: ik_Foor_R_031
            property: "position"
            keyframeSource: "animations/ik_Foor_R_031_position_0.qad"
        }
        KeyframeGroup {
            target: spine_003_05
            property: "position"
            keyframeSource: "animations/spine_003_05_position_0.qad"
        }
        KeyframeGroup {
            target: spine_003_05
            property: "rotation"
            keyframeSource: "animations/spine_003_05_rotation_0.qad"
        }
    }
    Timeline {
        id: armature_walk2_timeline
        objectName: "Armature|walk2"
        property real framesPerSecond: 1000
        startFrame: 0
        endFrame: 1280
        currentFrame: 0
        enabled: true
        animations: TimelineAnimation {
            duration: 1280
            from: 0
            to: 1280
            running: true
            loops: Animation.Infinite
        }
        KeyframeGroup {
            target: hand_IK_L_025
            property: "position"
            keyframeSource: "animations/hand_IK_L_025_position_1.qad"
        }
        KeyframeGroup {
            target: pelvis_R_020
            property: "position"
            keyframeSource: "animations/pelvis_R_020_position_1.qad"
        }
        KeyframeGroup {
            target: thigh_R_021
            property: "rotation"
            keyframeSource: "animations/thigh_R_021_rotation_1.qad"
        }
        KeyframeGroup {
            target: shin_R_022
            property: "rotation"
            keyframeSource: "animations/shin_R_022_rotation_1.qad"
        }
        KeyframeGroup {
            target: foot_R_023
            property: "rotation"
            keyframeSource: "animations/foot_R_023_rotation_1.qad"
        }
        KeyframeGroup {
            target: toe_R_024
            property: "rotation"
            keyframeSource: "animations/toe_R_024_rotation_1.qad"
        }
        KeyframeGroup {
            target: pelvis_L_00
            property: "position"
            keyframeSource: "animations/pelvis_L_00_position_1.qad"
        }
        KeyframeGroup {
            target: thigh_L_016
            property: "rotation"
            keyframeSource: "animations/thigh_L_016_rotation_1.qad"
        }
        KeyframeGroup {
            target: shin_L_017
            property: "position"
            Keyframe {
                frame: 0
                value: Qt.vector3d(6.51926e-09, 0.471651, 2.67755e-09)
            }
        }
        KeyframeGroup {
            target: shin_L_017
            property: "rotation"
            keyframeSource: "animations/shin_L_017_rotation_1.qad"
        }
        KeyframeGroup {
            target: foot_L_018
            property: "rotation"
            keyframeSource: "animations/foot_L_018_rotation_1.qad"
        }
        KeyframeGroup {
            target: toe_L_019
            property: "position"
            keyframeSource: "animations/toe_L_019_position_1.qad"
        }
        KeyframeGroup {
            target: toe_L_019
            property: "rotation"
            keyframeSource: "animations/toe_L_019_rotation_1.qad"
        }
        KeyframeGroup {
            target: head_07
            property: "position"
            keyframeSource: "animations/head_07_position_1.qad"
        }
        KeyframeGroup {
            target: head_07
            property: "rotation"
            keyframeSource: "animations/head_07_rotation_1.qad"
        }
        KeyframeGroup {
            target: spine_002_04
            property: "position"
            keyframeSource: "animations/spine_002_04_position_1.qad"
        }
        KeyframeGroup {
            target: spine_002_04
            property: "rotation"
            keyframeSource: "animations/spine_002_04_rotation_1.qad"
        }
        KeyframeGroup {
            target: neck_06
            property: "position"
            keyframeSource: "animations/neck_06_position_1.qad"
        }
        KeyframeGroup {
            target: neck_06
            property: "rotation"
            keyframeSource: "animations/neck_06_rotation_1.qad"
        }
        KeyframeGroup {
            target: spine_001_03
            property: "position"
            keyframeSource: "animations/spine_001_03_position_1.qad"
        }
        KeyframeGroup {
            target: spine_001_03
            property: "rotation"
            keyframeSource: "animations/spine_001_03_rotation_1.qad"
        }
        KeyframeGroup {
            target: hand_IK_R_027
            property: "position"
            keyframeSource: "animations/hand_IK_R_027_position_1.qad"
        }
        KeyframeGroup {
            target: hand_L_011
            property: "position"
            keyframeSource: "animations/hand_L_011_position_1.qad"
        }
        KeyframeGroup {
            target: hand_L_011
            property: "rotation"
            keyframeSource: "animations/hand_L_011_rotation_1.qad"
        }
        KeyframeGroup {
            target: lower_arm_L_010
            property: "position"
            keyframeSource: "animations/lower_arm_L_010_position_1.qad"
        }
        KeyframeGroup {
            target: lower_arm_L_010
            property: "rotation"
            keyframeSource: "animations/lower_arm_L_010_rotation_1.qad"
        }
        KeyframeGroup {
            target: upper_arm_L_09
            property: "position"
            keyframeSource: "animations/upper_arm_L_09_position_1.qad"
        }
        KeyframeGroup {
            target: upper_arm_L_09
            property: "rotation"
            keyframeSource: "animations/upper_arm_L_09_rotation_1.qad"
        }
        KeyframeGroup {
            target: spine_02
            property: "position"
            keyframeSource: "animations/spine_02_position_1.qad"
        }
        KeyframeGroup {
            target: collar_L_08
            property: "rotation"
            keyframeSource: "animations/collar_L_08_rotation_1.qad"
        }
        KeyframeGroup {
            target: hand_R_015
            property: "position"
            keyframeSource: "animations/hand_R_015_position_1.qad"
        }
        KeyframeGroup {
            target: hand_R_015
            property: "rotation"
            keyframeSource: "animations/hand_R_015_rotation_1.qad"
        }
        KeyframeGroup {
            target: ik_Foor_L_029
            property: "position"
            keyframeSource: "animations/ik_Foor_L_029_position_1.qad"
        }
        KeyframeGroup {
            target: lower_arm_R_014
            property: "position"
            keyframeSource: "animations/lower_arm_R_014_position_1.qad"
        }
        KeyframeGroup {
            target: lower_arm_R_014
            property: "rotation"
            keyframeSource: "animations/lower_arm_R_014_rotation_1.qad"
        }
        KeyframeGroup {
            target: upper_arm_R_013
            property: "position"
            Keyframe {
                frame: 0
                value: Qt.vector3d(-0.00368272, 0.121146, -0.0764979)
            }
        }
        KeyframeGroup {
            target: upper_arm_R_013
            property: "rotation"
            keyframeSource: "animations/upper_arm_R_013_rotation_1.qad"
        }
        KeyframeGroup {
            target: collar_R_012
            property: "rotation"
            keyframeSource: "animations/collar_R_012_rotation_1.qad"
        }
        KeyframeGroup {
            target: ik_Foor_R_031
            property: "position"
            keyframeSource: "animations/ik_Foor_R_031_position_1.qad"
        }
        KeyframeGroup {
            target: spine_003_05
            property: "position"
            keyframeSource: "animations/spine_003_05_position_1.qad"
        }
        KeyframeGroup {
            target: spine_003_05
            property: "rotation"
            keyframeSource: "animations/spine_003_05_rotation_1.qad"
        }
    }
}
