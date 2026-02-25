## What changed

Describe the change and why it is needed.

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Refactor/maintenance

## Validation

List the commands/checks you ran and their results.

```sh
# example
helm lint charts/kubeclaw ...
helm template kubeclaw charts/kubeclaw ... | kubectl apply --dry-run=client -f -
```

## Production impact

- [ ] No behavior/default change
- [ ] Behavior/default change (explain below)
- [ ] Backward incompatible change (explain below)

## Checklist

- [ ] PR is focused on one issue/topic
- [ ] Docs updated for behavior/default changes
- [ ] No secrets/credentials included
- [ ] I verified this does not break singleton Gateway assumptions (`replicas: 1`)
