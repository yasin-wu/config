NAMESPACE="yasin-app"
FILE="templates/configmap.yaml"
debug:
	@helm install --dry-run --debug nginx ./ -n "$(NAMESPACE)"
tpl:
	@helm template ./ --output-dir tpl/ -n "$(NAMESPACE)"
tplf:
	@helm template ./ -n "$(NAMESPACE)" --show-only "$(FILE)"
package:
	@helm packaget ./
install:
	@helm install nginx ./ -n "$(NAMESPACE)" --create-namespace
upgrade:
	@helm upgrade nginx ./ -n "$(NAMESPACE)"
uninstall:
	@helm uninstall nginx -n "$(NAMESPACE)"