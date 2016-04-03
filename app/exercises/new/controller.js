import Base from '../base/controller';

export default Base.extend({
  actions: {
    cancel() {
      this.get('model').rollbackAttributes();
      this.transitionToRoute('exercises');

      return false;
    },
  }
});