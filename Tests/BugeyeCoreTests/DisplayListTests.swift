import BugeyeCore
import Foundation
import Testing

@Suite struct DisplayListTests {
    static let sample = DisplayList(
        size: Size2D(width: 100, height: 50),
        commands: [
            .fillPath(.rect(Rect2D(x: 0, y: 0, width: 100, height: 50)), color: RGBAColor(red: 1, green: 0.5, blue: 0)),
            .strokePath(
                VectorPath([
                    .move(to: Point2D(x: 1, y: 2)), .quadCurve(to: Point2D(x: 5, y: 6), control: Point2D(x: 3, y: 4)),
                ]),
                color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5), lineWidth: 2),
            .image(imageID: "img-1", rect: Rect2D(x: 10, y: 10, width: 20, height: 20)),
            .textRun(
                "Step 1/3", origin: Point2D(x: 4, y: 40), font: FontDescriptor(name: "SF Pro", size: 13, weight: 0.3),
                color: RGBAColor(red: 1, green: 1, blue: 1)),
            .blurRegion(Rect2D(x: 50, y: 0, width: 50, height: 50), radius: 12),
        ])

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(Self.sample)
        #expect(try JSONDecoder().decode(DisplayList.self, from: data) == Self.sample)
    }

    @Test func goldenJSONIsStable() throws {
        let golden = """
            {
              "commands" : [
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
                              "x" : 100,
                              "y" : 0
                            }
                          }
                        },
                        {
                          "line" : {
                            "to" : {
                              "x" : 100,
                              "y" : 50
                            }
                          }
                        },
                        {
                          "line" : {
                            "to" : {
                              "x" : 0,
                              "y" : 50
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
                      "blue" : 0,
                      "green" : 0.5,
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
                              "x" : 1,
                              "y" : 2
                            }
                          }
                        },
                        {
                          "quadCurve" : {
                            "control" : {
                              "x" : 3,
                              "y" : 4
                            },
                            "to" : {
                              "x" : 5,
                              "y" : 6
                            }
                          }
                        }
                      ]
                    },
                    "color" : {
                      "alpha" : 0.5,
                      "blue" : 0,
                      "green" : 0,
                      "red" : 0
                    },
                    "lineWidth" : 2
                  }
                },
                {
                  "image" : {
                    "imageID" : "img-1",
                    "rect" : {
                      "origin" : {
                        "x" : 10,
                        "y" : 10
                      },
                      "size" : {
                        "height" : 20,
                        "width" : 20
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
                      "name" : "SF Pro",
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
                        "x" : 50,
                        "y" : 0
                      },
                      "size" : {
                        "height" : 50,
                        "width" : 50
                      }
                    },
                    "radius" : 12
                  }
                }
              ],
              "size" : {
                "height" : 50,
                "width" : 100
              }
            }
            """
        #expect(try Self.sample.goldenJSON() == golden)
    }
}
