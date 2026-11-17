# Service director / producer: switcher control and Dante routing.
{
  production.apps = [ "atem-software-control" "dante-controller" ];
  # No pager role: the service director runs the producer.
}
