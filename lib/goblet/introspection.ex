defmodule Goblet.IntrospectionGoblet do
  @moduledoc false
  use Goblet, from: "./lib/goblet/introspection.json"
end

defmodule Goblet.Introspection do
  @moduledoc false
  use Goblet.IntrospectionGoblet

  query "Query" do
    __schema do
      queryType do
        name
      end

      mutationType do
        name
      end

      subscriptionType do
        name
      end

      types do
        kind
        name

        fields(includeDeprecated: true) do
          name

          args do
            name

            type do
              kind
              name

              ofType do
                kind
                name

                ofType do
                  kind
                  name

                  ofType do
                    kind
                    name

                    ofType do
                      kind
                      name

                      ofType do
                        kind
                        name

                        ofType do
                          kind
                          name

                          ofType do
                            kind
                            name
                          end
                        end
                      end
                    end
                  end
                end
              end
            end

            defaultValue
          end

          type do
            kind
            name

            ofType do
              kind
              name

              ofType do
                kind
                name

                ofType do
                  kind
                  name

                  ofType do
                    kind
                    name

                    ofType do
                      kind
                      name

                      ofType do
                        kind
                        name

                        ofType do
                          kind
                          name
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          isDeprecated
          deprecationReason
        end

        inputFields do
          name

          type do
            kind
            name

            ofType do
              kind
              name

              ofType do
                kind
                name

                ofType do
                  kind
                  name

                  ofType do
                    kind
                    name

                    ofType do
                      kind
                      name

                      ofType do
                        kind
                        name

                        ofType do
                          kind
                          name
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          defaultValue
        end

        interfaces do
          kind
          name

          ofType do
            kind
            name

            ofType do
              kind
              name

              ofType do
                kind
                name

                ofType do
                  kind
                  name

                  ofType do
                    kind
                    name

                    ofType do
                      kind
                      name

                      ofType do
                        kind
                        name
                      end
                    end
                  end
                end
              end
            end
          end
        end

        enumValues(includeDeprecated: true) do
          name
          isDeprecated
          deprecationReason
        end

        possibleTypes do
          kind
          name

          ofType do
            kind
            name

            ofType do
              kind
              name

              ofType do
                kind
                name

                ofType do
                  kind
                  name

                  ofType do
                    kind
                    name

                    ofType do
                      kind
                      name

                      ofType do
                        kind
                        name
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      directives do
        name
        locations

        args do
          name

          type do
            kind
            name

            ofType do
              kind
              name

              ofType do
                kind
                name

                ofType do
                  kind
                  name

                  ofType do
                    kind
                    name

                    ofType do
                      kind
                      name

                      ofType do
                        kind
                        name

                        ofType do
                          kind
                          name
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          defaultValue
        end
      end
    end
  end
end
