import { _cleanState, _createRunId } from '../src/state.ts'

const cmd = process.argv[2]

switch (cmd) {
  case 'create': {
    const runId = _createRunId({ clean: false })
    console.log(`✓ runId=${runId}`)
    break
  }
  case 'create:clean': {
    const runId = _createRunId({ clean: true })
    console.log(`✓ cleaned, runId=${runId}`)
    break
  }
  case 'clean':
    _cleanState()
    console.log('✓ vitest-state/ cleaned')
    break
  default:
    console.error(`unknown command: ${cmd ?? '(none)'}\nusage: tsx scripts/state.ts <create|create:clean|clean>`)
    process.exit(2)
}
