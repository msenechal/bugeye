import BugeyeCore
import Foundation
import Testing

@Suite struct DisplayListTests {
    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let box = Rect2D(x: 0, y: 0, width: 4, height: 2)

    /// One of every command (contracts §4.1.7), with the defaults and every non-default option.
    static let sample = DisplayList(
        size: Size2D(width: 100, height: 50),
        commands: [
            .pushGroup(
                GroupStyle(
                    opacity: 0.5,
                    shadow: Shadow(offset: Point2D(x: 0, y: 2), blur: 4, color: RGBAColor(red: 0, green: 0, blue: 0)),
                    isolated: true, bounds: box)),
            .clip(.rect(box)),
            .fillPath(.rect(box), color: white),
            .strokePath(.rect(box), color: white, lineWidth: 2),
            .strokePath(.rect(box), color: white, lineWidth: 3, cap: .round, join: .bevel, dash: [4, 2]),
            .popGroup,
            .fillLinearGradient(
                .rect(box), stops: [GradientStop(location: 0, color: white), GradientStop(location: 1, color: white)],
                start: Point2D(x: 0, y: 0), end: Point2D(x: 4, y: 0)),
            .image(imageID: "img-1", rect: box),
            .textRun(
                "Step 1/3", origin: Point2D(x: 4, y: 40),
                font: FontDescriptor(name: FontDescriptor.systemFontName, size: 13, weight: 0.3), color: white),
            .blurRegion(box, sourceImageID: "img-1", sourceRect: box, effect: .pixelate(cellSize: 8)),
            .blurRegion(box, sourceImageID: "img-1", sourceRect: box, effect: .gaussian(radius: 12)),
        ])

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(Self.sample)
        #expect(try JSONDecoder().decode(DisplayList.self, from: data) == Self.sample)
    }

    @Test func goldenJSONIsStable() throws {
        #expect(try Self.sample.goldenJSON() == Self.golden)
    }

    /// Checked by eye against §4.1.7 when written: every command, both defaults and options of `strokePath`.
    static let golden = """
        {
          "commands" : [
            {
              "pushGroup" : {
                "_0" : {
                  "bounds" : {
                    "origin" : {
                      "x" : 0,
                      "y" : 0
                    },
                    "size" : {
                      "height" : 2,
                      "width" : 4
                    }
                  },
                  "isolated" : true,
                  "opacity" : 0.5,
                  "shadow" : {
                    "blur" : 4,
                    "color" : {
                      "alpha" : 1,
                      "blue" : 0,
                      "green" : 0,
                      "red" : 0
                    },
                    "offset" : {
                      "x" : 0,
                      "y" : 2
                    }
                  }
                }
              }
            },
            {
              "clip" : {
                "_0" : {
                  "elements" : [
                    {
                      "move" : {
                        "to" : {
                          "x" : 0,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 0,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "close" : {

                      }
                    }
                  ]
                }
              }
            },
            {
              "fillPath" : {
                "_0" : {
                  "elements" : [
                    {
                      "move" : {
                        "to" : {
                          "x" : 0,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 0,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "close" : {

                      }
                    }
                  ]
                },
                "color" : {
                  "alpha" : 1,
                  "blue" : 1,
                  "green" : 1,
                  "red" : 1
                }
              }
            },
            {
              "strokePath" : {
                "_0" : {
                  "elements" : [
                    {
                      "move" : {
                        "to" : {
                          "x" : 0,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 0,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "close" : {

                      }
                    }
                  ]
                },
                "cap" : "butt",
                "color" : {
                  "alpha" : 1,
                  "blue" : 1,
                  "green" : 1,
                  "red" : 1
                },
                "dash" : [

                ],
                "join" : "miter",
                "lineWidth" : 2
              }
            },
            {
              "strokePath" : {
                "_0" : {
                  "elements" : [
                    {
                      "move" : {
                        "to" : {
                          "x" : 0,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 0,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "close" : {

                      }
                    }
                  ]
                },
                "cap" : "round",
                "color" : {
                  "alpha" : 1,
                  "blue" : 1,
                  "green" : 1,
                  "red" : 1
                },
                "dash" : [
                  4,
                  2
                ],
                "join" : "bevel",
                "lineWidth" : 3
              }
            },
            {
              "popGroup" : {

              }
            },
            {
              "fillLinearGradient" : {
                "_0" : {
                  "elements" : [
                    {
                      "move" : {
                        "to" : {
                          "x" : 0,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 0
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 4,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "line" : {
                        "to" : {
                          "x" : 0,
                          "y" : 2
                        }
                      }
                    },
                    {
                      "close" : {

                      }
                    }
                  ]
                },
                "end" : {
                  "x" : 4,
                  "y" : 0
                },
                "start" : {
                  "x" : 0,
                  "y" : 0
                },
                "stops" : [
                  {
                    "color" : {
                      "alpha" : 1,
                      "blue" : 1,
                      "green" : 1,
                      "red" : 1
                    },
                    "location" : 0
                  },
                  {
                    "color" : {
                      "alpha" : 1,
                      "blue" : 1,
                      "green" : 1,
                      "red" : 1
                    },
                    "location" : 1
                  }
                ]
              }
            },
            {
              "image" : {
                "imageID" : "img-1",
                "rect" : {
                  "origin" : {
                    "x" : 0,
                    "y" : 0
                  },
                  "size" : {
                    "height" : 2,
                    "width" : 4
                  }
                }
              }
            },
            {
              "textRun" : {
                "_0" : "Step 1/3",
                "color" : {
                  "alpha" : 1,
                  "blue" : 1,
                  "green" : 1,
                  "red" : 1
                },
                "font" : {
                  "name" : "system",
                  "size" : 13,
                  "weight" : 0.3
                },
                "origin" : {
                  "x" : 4,
                  "y" : 40
                }
              }
            },
            {
              "blurRegion" : {
                "_0" : {
                  "origin" : {
                    "x" : 0,
                    "y" : 0
                  },
                  "size" : {
                    "height" : 2,
                    "width" : 4
                  }
                },
                "effect" : {
                  "pixelate" : {
                    "cellSize" : 8
                  }
                },
                "sourceImageID" : "img-1",
                "sourceRect" : {
                  "origin" : {
                    "x" : 0,
                    "y" : 0
                  },
                  "size" : {
                    "height" : 2,
                    "width" : 4
                  }
                }
              }
            },
            {
              "blurRegion" : {
                "_0" : {
                  "origin" : {
                    "x" : 0,
                    "y" : 0
                  },
                  "size" : {
                    "height" : 2,
                    "width" : 4
                  }
                },
                "effect" : {
                  "gaussian" : {
                    "radius" : 12
                  }
                },
                "sourceImageID" : "img-1",
                "sourceRect" : {
                  "origin" : {
                    "x" : 0,
                    "y" : 0
                  },
                  "size" : {
                    "height" : 2,
                    "width" : 4
                  }
                }
              }
            }
          ],
          "size" : {
            "height" : 50,
            "width" : 100
          }
        }
        """

    @Test func theSystemFontHasAFixedName() {
        #expect(FontDescriptor.systemFontName == "system")
    }

    @Test func balanceNeedsMatchedGroupsAndClipsInsideOne() {
        func list(_ commands: [DisplayCommand]) -> DisplayList {
            DisplayList(size: Size2D(width: 1, height: 1), commands: commands)
        }
        let rect = VectorPath.rect(Self.box)
        #expect(Self.sample.isBalanced)
        #expect(list([]).isBalanced)
        #expect(list([.pushGroup(GroupStyle()), .pushGroup(GroupStyle()), .popGroup, .popGroup]).isBalanced)
        #expect(!list([.pushGroup(GroupStyle())]).isBalanced)
        #expect(!list([.popGroup]).isBalanced)
        #expect(!list([.popGroup, .pushGroup(GroupStyle())]).isBalanced)
        #expect(!list([.clip(rect)]).isBalanced)
        #expect(!list([.pushGroup(GroupStyle()), .popGroup, .clip(rect)]).isBalanced)
    }

    @Test func groupStyleDefaults() {
        let style = GroupStyle()
        #expect(style.opacity == 1 && style.shadow == nil && !style.isolated && style.bounds == nil)
    }

    @Test func ellipseIsFourCubicsClockwiseFromTheRight() {
        let k = 0.5522847498
        let path = VectorPath.ellipse(in: Rect2D(x: 10, y: 20, width: 40, height: 20))
        // Centre (30, 30), radii 20 and 10. y grows downward, so clockwise goes right → bottom → left → top.
        #expect(
            path.elements == [
                .move(to: Point2D(x: 50, y: 30)),
                .curve(
                    to: Point2D(x: 30, y: 40), control1: Point2D(x: 50, y: 30 + 10 * k),
                    control2: Point2D(x: 30 + 20 * k, y: 40)),
                .curve(
                    to: Point2D(x: 10, y: 30), control1: Point2D(x: 30 - 20 * k, y: 40),
                    control2: Point2D(x: 10, y: 30 + 10 * k)),
                .curve(
                    to: Point2D(x: 30, y: 20), control1: Point2D(x: 10, y: 30 - 10 * k),
                    control2: Point2D(x: 30 - 20 * k, y: 20)),
                .curve(
                    to: Point2D(x: 50, y: 30), control1: Point2D(x: 30 + 20 * k, y: 20),
                    control2: Point2D(x: 50, y: 30 - 10 * k)),
                .close,
            ])
    }

    @Test func aZeroRadiusRoundedRectIsARect() {
        let rect = Rect2D(x: 1, y: 2, width: 30, height: 10)
        #expect(VectorPath.roundedRect(rect, cornerRadius: 0) == .rect(rect))
        #expect(VectorPath.roundedRect(rect, cornerRadius: -3) == .rect(rect))
    }

    @Test func roundedRectCornersAreQuarterCubics() {
        let k = 0.5522847498
        let path = VectorPath.roundedRect(Rect2D(x: 0, y: 0, width: 30, height: 10), cornerRadius: 2)
        #expect(
            path.elements == [
                .move(to: Point2D(x: 2, y: 0)),
                .line(to: Point2D(x: 28, y: 0)),
                .curve(
                    to: Point2D(x: 30, y: 2), control1: Point2D(x: 28 + 2 * k, y: 0),
                    control2: Point2D(x: 30, y: 2 - 2 * k)),
                .line(to: Point2D(x: 30, y: 8)),
                .curve(
                    to: Point2D(x: 28, y: 10), control1: Point2D(x: 30, y: 8 + 2 * k),
                    control2: Point2D(x: 28 + 2 * k, y: 10)),
                .line(to: Point2D(x: 2, y: 10)),
                .curve(
                    to: Point2D(x: 0, y: 8), control1: Point2D(x: 2 - 2 * k, y: 10),
                    control2: Point2D(x: 0, y: 8 + 2 * k)),
                .line(to: Point2D(x: 0, y: 2)),
                .curve(
                    to: Point2D(x: 2, y: 0), control1: Point2D(x: 0, y: 2 - 2 * k),
                    control2: Point2D(x: 2 - 2 * k, y: 0)),
                .close,
            ])
    }

    @Test func theRadiusIsClampedToHalfTheShorterSide() {
        let rect = Rect2D(x: 0, y: 0, width: 30, height: 10)
        #expect(VectorPath.roundedRect(rect, cornerRadius: 50) == VectorPath.roundedRect(rect, cornerRadius: 5))
        #expect(VectorPath.roundedRect(rect, cornerRadius: 5).elements[1] == .line(to: Point2D(x: 25, y: 0)))
    }
}
