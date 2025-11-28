import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import EmberObject, { action, computed } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import discourseTag from "discourse/helpers/discourse-tag";
import { findOrResetCachedTopicList } from "discourse/lib/cached-topic-list";
import { cook } from "discourse/lib/text";
import TlpFeaturedTopic from "./tlp-featured-topic";

export default class TlpFeaturedTopicsComponent extends Component {
  @service appEvents;
  @service store;
  @service session;

  @tracked featuredTitle = "";
  @tracked featuredTopics = [];

  constructor() {
    super(...arguments);
    this.appEvents.trigger("topic:refresh-timeline-position");

    if (this.showFeaturedTitle) {
      const raw = settings.topic_list_featured_title;
      cook(raw).then((cooked) => (this.featuredTitle = cooked));
    }
  }

  @action
  async getFeaturedTopics() {
    // 如果没配置 tag，直接什么都不显示
    if (!settings.topic_list_featured_images_tag) {
      this.featuredTopics = [];
      return;
    }
  
    const tagName = settings.topic_list_featured_images_tag;
    let allTopics = [];
    let page = 0;
  
    // 循环拉取这个 tag 下的所有话题（每页最多 30 条）
    while (true) {
      const result = await this.store.findFiltered("topicList", {
        filter: `tag/${tagName}`,
        params: { page },
      });
  
      const topics = result?.topic_list?.topics || [];
      if (topics.length === 0) break;
  
      allTopics.push(...topics);
      page++;
  
      // 安全阀：最多 500 条，防止某个 tag 太多把浏览器卡死
      if (allTopics.length >= 500) {
        console.warn("Featured topics 超过 500 条，已自动截断");
        break;
      }
  
      // 最后一页通常不足 30 条，直接退出
      if (topics.length < 30) break;
    }
  
    // ==================== 关键修复：先排序/随机，再截取数量 ====================
    let finalTopics = allTopics;
  
    // 1. 可选：只保留当前分类下的帖子
    if (
      this.args.category &&
      settings.topic_list_featured_images_from_current_category_only
    ) {
      finalTopics = finalTopics.filter(
        (topic => topic.category_id === this.args.category.id
      );
    }
  
    // 2. 先处理排序 / 随机（重点！）
    if (settings.topic_list_featured_images_order === "random") {
      // Fisher-Yates 洗牌，真正的全量随机
      for (let i = finalTopics.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [finalTopics[i], finalTopics[j]] = [finalTopics[j], finalTopics[i]];
      }
    } else if (settings.topic_list_featured_images_order === "created") {
      // 按创建时间倒序（最新的最上面）
      finalTopics.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    }
    // 其他情况保持 Discourse 默认 activity 顺序
  
    // 3. 最后才做数量限制（这时候已经是随机或排好序的了）
    if (settings.topic_list_featured_images_count > 0) {
      finalTopics = finalTopics.slice(0, settings.topic_list_featured_images_count);
    }
  
    // 赋值给模板使用
    this.featuredTopics = finalTopics;
  }

  @computed("featuredTopics")
  get showFeatured() {
    return (
      ((settings.topic_list_featured_images && this.args.category == null) ||
        (settings.topic_list_featured_images_category &&
          this.args.category !== null)) &&
      this.featuredTopics.length > 0
    );
  }

  @computed
  get showFeaturedTitle() {
    return settings.topic_list_featured_title;
  }

  @computed
  get featuredTags() {
    return settings.topic_list_featured_images_tag.split("|");
  }

  @computed
  get showFeaturedTags() {
    return this.featuredTags && settings.topic_list_featured_images_tag_show;
  }

  <template>
    <div
      {{didInsert this.getFeaturedTopics}}
      {{didUpdate this.getFeaturedTopics}}
      class="tlp-featured-topics {{if this.showFeatured 'has-topics'}}"
    >
      {{#if this.showFeatured}}
        {{#if this.showFeaturedTitle}}
          <div class="featured-title">
            {{this.featuredTitle}}
          </div>
        {{/if}}
        <div class="topics">
          {{#each this.featuredTopics as |t|}}
            <TlpFeaturedTopic @topic={{t}} />
          {{/each}}
        </div>
        {{#if this.showFeaturedTags}}
          <div class="featured-tags">
            {{#each this.featuredTags as |tag|}}
              {{discourseTag tag}}
            {{/each}}
          </div>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
